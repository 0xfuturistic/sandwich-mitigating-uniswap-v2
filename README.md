# 🥪🦄 Sandwich-Resistant Uniswap V2

<img src="unicorn.png" width="55%">

> **Background:** Matheus V. X. Ferreira and David C. Parkes. _Credible Decentralized Exchange Design via Verifiable Sequencing Rules._ URL: https://arxiv.org/pdf/2209.15569.

Uniswap V2 is minimally modified to implement the Greedy Sequencing Rule (GSR), a verifiable sequencing rule that mitigates sandwich attacks.

## The Greedy Sequencing Rule (GSR)

The GSR is a verifiable sequencing rule that provides strong execution guarantees for users. For a user transaction $A$ that the proposer includes in the block, the GSR ensures one of the following (Theorem 5.2, p. 22):

1. The user can efficiently detect if the proposer didn't respect the rule.
2. The execution price of $A$ for the user is at least as good as if $A$ was the only transaction in the block.
3. The execution price of $A$ is worse than this standalone price but the proposer does not gain when including $A$ in the block.

The rule proceeds as follows:

1. Initialize an empty execution ordering $T$.
2. Partition outstanding transactions into buy orders ($B_{buy}$) and sell orders ($B_{sell}$).
3. While both $B_{buy}$ and $B_{sell}$ are non-empty:
    - If current token 1 reserves ≥ initial token 1 reserves:
        - Append any order from $B_{buy}$ to $T$ and remove it from $B_{buy}$.
    - Else:
        - Append any order from $B_{sell}$ to $T$ and remove it from $B_{sell}$.
4. If any orders remain, append them to $T$ in any order.

The rule exploits the Duality Theorem (Theorem 5.1, p. 20): at any state in a two-token liquidity pool, either all buy orders or all sell orders will receive a better execution price than at the initial state.

## Implementation

Our implementation modifies Uniswap V2 to incorporate the GSR. Unlike the original paper's verifier (Algorithm 4), which checks the entire order of transactions in a block every time, our approach verifies new transactions in real-time. This results in a constant-time verification algorithm for new transactions, improving efficiency over the linear-time algorithm in the original paper.

The key changes are in the swap function, adding 24 lines of code:

```solidity
function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
    // ... existing swap logic ...

    if (block.number > sequencingRuleInfo.blockNumber) {
        // We have a new block, so we must reset the sequencing rule info
        sequencingRuleInfo.blockNumber = block.number;
        sequencingRuleInfo.reserve0Start = _reserve0;
        sequencingRuleInfo.emptyBuysOrSells = false;
    } else {
        // Get the swap type (i.e., buy or sell)
        SwapType swapType = amount0Out > 0 ? SwapType.BUY : SwapType.SELL;

        if (sequencingRuleInfo.emptyBuysOrSells) {
            // If we have run out of buys or sells, the swap type must be the same as for the tail swap
            require(swapType == sequencingRuleInfo.tailSwapType, "UniswapV2: Swap violates sequencing rule");
        } else {
            // Find the required swap type so we can validate against it
            SwapType requiredSwapType = _reserve0 >= sequencingRuleInfo.reserve0Start ? SwapType.SELL : SwapType.BUY;

            if (swapType != requiredSwapType) {
                // We must have run out of buys or sells
                sequencingRuleInfo.emptyBuysOrSells = true;

                // Set the tail swap type
                sequencingRuleInfo.tailSwapType = swapType;
            }
        }
    }

    // ... continue with swap execution ...
}
```

This implementation is computationally efficient and verifiable, allowing anyone to check if the new transaction leads to a valid ordering, following from an existing valid ordering according to the GSR. It does not have any external depedencies, and it does not dependent on any off-chain computation, trust in external parties, or additional infrastructure.


## Benefits

This solution is effective because it:

- Protects against sandwich attacks.
- Has a constant-time overhead on the swap function.
- Preserves atomic composability.
- Requires minimal changes to the existing Uniswap v2 codebase.

## Limitations

While the GSR prevents classic sandwich attacks, it doesn't eliminate all forms of MEV. The paper proves that for any sequencing rule, there exist scenarios where proposers can obtain risk-free profits (Theorem 4.2, p. 17-18).

Multi-block MEV remains a consideration, where a proposer that proposes consecutive blocks could influence the initial price used by a given swap. Nevertheless, this can potentially be addressed by updating this initial price less frequently or using a moving average over several past blocks instead. Either approach would raise the costs associated with this vector.
