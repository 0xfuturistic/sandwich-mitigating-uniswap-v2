# 🥪🦄 Sandwich-Resistant Uniswap V2

<img src="unicorn.png" width="60%">

> **Background:** Matheus V. X. Ferreira and David C. Parkes. _Credible Decentralized Exchange Design via Verifiable Sequencing Rules._ URL: https://arxiv.org/pdf/2209.15569.

We modify Uniswap V2 to implement the Greedy Sequencing Rule (GSR), a verifiable sequencing rule that prevents sandwich attacks and provides the following guarantees (Theorem 5.2, p. 22):
1. The user's execution price is at least as good as if their swap was alone in the block.
2. If their price is worse, the proposer doesn't profit from including the transaction.
3. The protocol can detect rule violations (i.e., the proposer didn't follow the GSR).

## How It Works
The swap function in `UniswapV2Pair` is modified to enforce the GSR, which works as follows (Algorithm 3, p. 20):
1. Initialize an empty execution ordering T.
2. Partition outstanding transactions into buy orders (B_buy) and sell orders (B_sell).
3. While both B_buy and B_sell are non-empty:
    - If current token 1 reserves ≥ initial token 1 reserves:
        - Append any order from B_buy to T 
    - Else:
        - Append any order from B_sell to T
4. If any orders remain, append them to T in any order.

This rule exploits a key property of two-token liquidity pools: at any state, either all buy orders or all sell orders will receive a better execution price than at the initial state (Theorem 5.1 "Duality Theorem", p. 20).

### Algorithm

The implementation involves adding 24 lines of code to the swap function. After each swap, the protocol runs the following algorithm:
1. If this is a new block, set the sequencing rule info, setting the initial state to the pair's current reserves of token 0.
2. Else, check whether we had already run out of buy or sell orders before the swap.
    - If we had, validate that the type (i.e., buy or sell) of the swap matches the type of the swaps in the tail of the permutation under the GSR.
3. Else, if we hadn't run out of buy or sell orders before the swap, compare the current reserves to the initial state to determine the required order type (i.e., a buy or sell) according to the sequencing rule.
    - If the swap types don't match, register that we must have run out of buy or sell orders. The type of the swap now makes up the type of the swaps in the tail of the permutation under the GSR.


```solidity
function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
    ...
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
}
```

This implementation is computationally efficient (Definition 3.2, p. 13) and verifiable (Definition 3.4, p. 15), allowing anyone to check if the execution ordering follows the GSR. It does not have any external depedencies, and it does not dependent on any off-chain computation, trust in external parties, or additional infrastructure.

## Benefits

This solution is effective because it:

- Protects against sandwich attacks (Theorem 5.2, p. 22).
- Has a constant-time overhead on the swap function.
- Preserves atomic composability.
- Requires minimal changes to the existing Uniswap v2 codebase.

## Limitations

While the GSR prevents classic sandwich attacks, it doesn't eliminate all forms of miner extractable value (MEV). The paper proves that for any sequencing rule, there exist scenarios where miners can obtain risk-free profits (Theorem 4.2, p. 17-18).

Multi-block MEV remains a consideration, where a proposer that proposes consecutive blocks could influence the initial price used by a given swap. Nevertheless, this can potentially be addressed by updating this initial price less frequently or using a moving average over several past blocks instead. Either approach would raise the costs associated with this vector.
