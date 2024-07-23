# 🥪🦄 Sandwich-Resistant Uniswap V2

> Background: https://arxiv.org/pdf/2209.15569

The core idea is to modify the swap function to enforce a verifiable sequencing rule, the Greedy Sequencing Rule (GSR), which prevents sandwich attacks.

Here's how it works:

1. For each swap, the protocol validates adherence to the GSR.
2. The GSR ensures that for any user transaction:
    1. The protocol detects rule violations.
    2. The user's execution price is at least as good as if their swap was alone in the block.
    3. If the price is worse, the proposer doesn't profit from including the transaction.

The implementation involves adding about 24 lines of code to the swap function, introducing only a constant time overhead.

After each swap, the protocol runs the following algorithm:

1. Check if we've run out of buy or sell orders.
    1. If so, validate that the remaining orders are of the type we haven’t run out of.
2. If not, compare current state to initial state to determine required order type (i.e., a buy or sell) according to the sequencing rule.
3. Validate the swap matches the required type.
4. If validation fails, register that we must have run out of buy or sell orders.

The algorithm is implemented in https://github.com/0xfuturistic/sandwich-resistant-uniswap-v2/blob/main/src/UniswapV2Pair.sol#L203C1-L231C10

This solution is effective because it:

- Protects against sandwich attacks effectively.
- Requires no off-chain computation, trust in external parties, or additional infrastructure.
- Preserves atomic composability.
- Requires minimal changes to the existing Uniswap v2 codebase.

Multi-block MEV remains a consideration, however, where a consecutive-blocks proposer could influence the benchmark price for the block used for evaluating the user’s execution price. Nevertheless, this can be addressed by updating this value less frequently or using a moving average over several past blocks instead. Either approach would raise the costs associated with this vector.