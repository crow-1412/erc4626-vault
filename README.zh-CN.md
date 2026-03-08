# ERC-4626 金库项目（中文说明）

> 一个生产级 Solidity 金库合约，具备手续费、暂停控制、防重入和完整测试体系。
> 适合用于 Web3 合约岗作品集展示。

---

## 这个项目是做什么的

把它理解成**链上理财账户**：

1. 用户存入 USDC，获得"份额"（shares）
2. 金库持有这些 USDC
3. 管理员注入收益（`harvest`），每份 share 随之升值
4. 用户可随时按份额赎回资产

存取时可按比例收取手续费，最高不超过 10%。

---

## 核心流程图

```
用户存入 USDC
      │
      ▼
  ┌─────────────────────────────────┐
  │ deposit(assets, receiver)       │
  │  1. 扣除手续费 → feeRecipient   │
  │  2. 计算 shares（存入前估值）    │
  │  3. 铸造 shares 给 receiver     │
  └─────────────────────────────────┘
      │
      ▼
  用户持有 shares（代表金库份额）
      │
      │   ← 管理员调用 harvest(amount)
      │       注入收益，share price 上涨
      │
      ▼
  ┌─────────────────────────────────┐
  │ redeem(shares, receiver, owner) │
  │  1. 计算对应资产（含收益）       │
  │  2. 烧毁 shares                 │
  │  3. 扣除手续费 → feeRecipient   │
  │  4. 转出净资产给 receiver        │
  └─────────────────────────────────┘
      │
      ▼
  用户收到 USDC（本金 + 收益 - 手续费）
```

---

## 核心功能

| 功能 | 说明 |
|------|------|
| `deposit / mint` | 存入资产，获得份额 |
| `withdraw / redeem` | 按份额或资产数量赎回 |
| `harvest(amount)` | 注入收益，推高 share price；`amount > 0` 才可调用，触发 `Harvested` 事件 |
| `pause / unpause` | 紧急暂停所有存取操作，仅限 owner |
| `setDepositFee / setWithdrawFee` | 调整手续费（≤ 10%），仅限 owner |
| `setFeeRecipient` | 修改手续费接收地址，不允许零地址 |

---

## 快速开始

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 克隆并构建
git clone <repo-url> && cd erc4626-vault
forge install
forge build

# 运行全部测试
forge test -v
```

---

## 测试结果

```
Ran 3 test suites: 55 tests passed, 0 failed, 0 skipped

  VaultTest.t.sol  — 46 unit tests  ✓
  VaultFuzz.t.sol  —  5 fuzz tests  ✓
  VaultInvariant.t.sol — 4 invariant tests  ✓
```

测试覆盖场景：存取款正确性、手续费精确计算、暂停状态拦截、权限控制、收益注入后 share price 变化、操作员授权、1 wei 极小额等边界场景。

---

## Gas Report（核心函数）

| 函数 | 平均 Gas | 最大 Gas |
|------|---------|---------|
| `deposit` | 138,710 | 166,704 |
| `withdraw` | 56,125 | 85,675 |
| `redeem` | 54,748 | 70,537 |
| `harvest` | 42,746 | 60,494 |
| `mint` | 52,476 | 98,725 |
| `pause` | 27,203 | 27,736 |

合约部署 Gas：**1,796,144**

---

## 关键设计决策：份额计算时机

`deposit` 时先调用 `previewDeposit(assetsAfterFee)` 再执行 token transfer。

这确保 share price 基于**转账前**的 `totalAssets()`，避免首次存款时因资产已进入合约导致份额计算为 0（经典的 inflation attack 入口）。

---

## 安全说明

详见 [SECURITY.md](./SECURITY.md)，包含：
- 重入风险与防护
- 暂停绕过防御
- 手续费上限设计

---

## 适合在简历里怎么描述

> 实现生产级 ERC-4626 Vault，具备手续费机制、权限管理、紧急暂停与防重入；
> 通过 55 个 unit / fuzz / invariant 测试验证会计正确性与核心安全性质。
