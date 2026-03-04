# ERC-4626 金库项目（中文说明）

这是一个基于 Solidity + Foundry 的 ERC-4626 资产金库示例项目，适合作为 Web3 合约岗作品集。

## 这个项目是做什么的

把它理解成“链上理财账户”：

1. 用户存入 USDC（`deposit` / `mint`）
2. 金库铸造份额代币（shares）给用户
3. 金库收益增加后（这里用 `harvest` 模拟），每份 share 更值钱
4. 用户可赎回资产（`withdraw` / `redeem`）
5. 存取时可收取手续费（basis points）

## 核心能力

- 标准兼容：遵循 ERC-4626 接口
- 费用体系：存款费 + 取款费（最高 10%）
- 安全控制：`Ownable`、`Pausable`、`ReentrancyGuard`
- 资产安全：使用 `SafeERC20`
- 会计可验证：`totalAssets()` 与 vault 实际余额一致
- 收益模拟：`harvest(amount)` 注入收益（`amount > 0`），并触发 `Harvested` 事件

## 测试覆盖

- 单元测试：46 个
- Fuzz 测试：5 个
- Invariant 测试：4 个
- 总计：55 个测试

重点验证：

- 份额计算和手续费扣除正确
- 暂停状态下关键路径不可用
- 无重入与权限绕过
- 不出现“凭空资产/凭空份额”

## 适合在简历里怎么描述

- “实现生产化 ERC-4626 Vault，支持 fee/pausable/reentrancy guard，并通过 unit + fuzz + invariant 测试验证核心安全与会计性质。”

