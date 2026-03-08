# SECURITY.md — 安全设计说明

> 本文件解释 SimpleVault 中三个核心安全决策的设计原因，面向代码审查与面试场景。

---

## 1. 重入风险与 ReentrancyGuard

### 风险来源

`deposit`、`withdraw`、`redeem` 都涉及外部合约调用（`safeTransferFrom` / `safeTransfer`）。
如果 token 是 ERC-777 或带有 hook 的合约，转账过程中可以回调本合约，在状态未更新时二次进入，造成资产或份额被多次取走。

### 防护方案

所有状态改变的入口函数统一加 `nonReentrant` 修饰符（OpenZeppelin `ReentrancyGuard`）。
它通过一个"锁"变量确保每次调用结束前，同一个交易不能再次进入任何被保护的函数。

```solidity
function deposit(...) public override nonReentrant whenNotPaused returns (uint256 shares) { ... }
function withdraw(...) public override nonReentrant whenNotPaused returns (uint256 shares) { ... }
function redeem(...)  public override nonReentrant whenNotPaused returns (uint256 assets) { ... }
```

### 为什么不用 Checks-Effects-Interactions 就足够？

CEI 是好实践，但本合约的 fee 逻辑需要在转账后执行额外的 `safeTransfer`，
纯靠 CEI 难以覆盖所有路径，显式锁更可靠，且 gas 开销极小（约 200 gas）。

---

## 2. 暂停绕过防御

### 风险来源

`Pausable` 通常只保护直接调用路径。如果 ERC-4626 的底层 `_update`（token 转账 hook）没有被保护，
攻击者可能通过 `transfer`、`transferFrom` 等路径绕过暂停，仍然移动份额。

### 防护方案

本合约在 `_update` 层面加了 `whenNotPaused`，覆盖所有 share token 的转移：

```solidity
function _update(address from, address to, uint256 value)
    internal override whenNotPaused
{
    super._update(from, to, value);
}
```

这意味着暂停后：
- `deposit / mint / withdraw / redeem` — 被 `whenNotPaused` 直接拦截
- `transfer / transferFrom` — 被 `_update` 中的 `whenNotPaused` 拦截
- mint / burn 操作 — 同样被 `_update` 拦截

所有 share 移动路径统一封闭，无绕过空间。

---

## 3. 手续费上限为什么是 10%

### 设计背景

手续费以 basis points（bps）表示，`1 bps = 0.01%`，`10% = 1000 bps`。

```solidity
uint256 public constant MAX_FEE = 1_000; // 10% max
uint256 public constant FEE_DENOMINATOR = 10_000;
```

### 为什么选 10%

- **防止 owner 作恶**：如果手续费无上限，owner 可将费率设为 100%，用户存入即归零。10% 是一个合理的上界，足以覆盖任何真实业务场景，同时限制最坏情况下的损失。
- **行业惯例**：主流 DeFi 协议（Yearn、Aave 等）的绩效费通常在 5%–20%，10% 作为上限与市场预期对齐。
- **setter 和 constructor 双重校验**：两处都执行上限检查，防止部署时和运行时各自产生漏洞。

```solidity
// constructor
if (depositFeeBps_ > MAX_FEE) revert FeeExceedsMax(depositFeeBps_, MAX_FEE);

// setter
function setDepositFee(uint256 newFeeBps) external onlyOwner {
    if (newFeeBps > MAX_FEE) revert FeeExceedsMax(newFeeBps, MAX_FEE);
    ...
}
```

### 精度风险

手续费计算使用整数除法：`fee = amount * feeBps / 10_000`。
极小额（如 1 wei）在低费率下可能舍入为 0，属于已知行为，对系统会计无影响（已有 `test_dust_deposit_1wei` 覆盖）。

---

## 其他安全点

| 风险 | 防护 |
|------|------|
| 零地址 feeRecipient | `constructor` 与 `setFeeRecipient` 均 revert ZeroAddress |
| harvest 注入 0 资产 | `if (amount == 0) revert ZeroAmount()` |
| share price 操控（inflation attack） | `previewDeposit` 在 token transfer 前调用，基于转入前 `totalAssets()` |
| 操作员权限滥用 | `withdraw/redeem` 非本人调用时走 `_spendAllowance` 扣配额 |
