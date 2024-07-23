# 🥪🦄 Sandwich-Resistant Uniswap V2

> **Background:** Matheus V. X. Ferreira and David C. Parkes. _Credible Decentralized Exchange Design via Verifiable Sequencing Rules._ URL: https://arxiv.org/pdf/2209.15569.

The core idea is to modify the swap function to enforce a verifiable sequencing rule, the Greedy Sequencing Rule (GSR), which prevents sandwich attacks.

Here's how it works:

1. For each swap, the protocol validates adherence to the GSR.
2. The GSR ensures that for any user transaction:
    1. The protocol detects rule violations.
    2. The user's execution price is at least as good as if their swap was alone in the block.
    3. If the price is worse, the proposer doesn't profit from including the transaction.

The implementation involves adding 24 lines of code to the swap function, introducing only a constant time overhead.

After each swap, the protocol runs the following algorithm:

1. If this is a new block, set the sequencing rule info, setting the initial state to the pair's current reserves of token 0.
2. Else, check whether we had already run out of buy or sell orders before the swap.
    - If we had, validate that the type (i.e., buy or sell) of the swap matches the type of the swaps in the tail of the permutation under the GSR.
3. Else, if we hadn't run out of buy or sell orders before the swap, compare the current reserves to the initial state to determine the required order type (i.e., a buy or sell) according to the sequencing rule.
    - If the swap types don't match, register that we must have run out of buy or sell orders. The type of the swap now makes up the type of the swaps in the tail of the permutation under the GSR.

The algorithm is implemented [here](https://github.com/0xfuturistic/sandwich-resistant-uniswap-v2/blob/main/src/UniswapV2Pair.sol#L203C1-L231C10). It does not have any external depedencies, and it does not dependent on any off-chain computation, trust in external parties, or additional infrastructure.

This solution is effective because it:

- Protects against sandwich attacks.
- Has a constant-time overhead on the swap function.
- Preserves atomic composability.
- Requires minimal changes to the existing Uniswap v2 codebase.

Multi-block MEV remains a consideration, however, where a proposer that proposes consecutive blocks could influence the initial price used by a given swap. Nevertheless, this can potentially be addressed by updating this initial price less frequently or using a moving average over several past blocks instead. Either approach would raise the costs associated with this vector.

Overall, this modification provides strong guarantees about execution quality while making sandwich attacks structurally unfeasible, all with minimal changes to the existing Uniswap v2 contracts.