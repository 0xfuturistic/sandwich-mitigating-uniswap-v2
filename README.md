# 🥪🦄 Sandwich-Resistant Uniswap V2

<img src="unicorn.png" width="55%">

> **Background:** Matheus V. X. Ferreira and David C. Parkes. _Credible Decentralized Exchange Design via Verifiable Sequencing Rules._ URL: https://arxiv.org/pdf/2209.15569.

Uniswap V2 is minimally modified to implement the Greedy Sequencing Rule (GSR), a verifiable sequencing rule that mitigates sandwich attacks.

## The Greedy Sequencing Rule (GSR)

The GSR provides strong execution guarantees for users. It leverages a key property of two-token liquidity pools: the Duality Theorem ([Theorem 5.1](#theorem-51-duality-theorem)), which states that at any given state, either all buy orders or all sell orders will receive a better execution price than at the initial state.

For any user transaction $A$ included in a block, the GSR ensures one of the following ([Theorem 5.2](#theorem-52-greedy-sequencing-rule-gsr)):

1. The user can efficiently detect if the proposer didn't respect the rule.
2. The execution price of $A$ for the user is at least as good as if $A$ was the only transaction in the block.
3. The execution price of $A$ is worse than this standalone price but the proposer does not gain when including $A$ in the block.

### GSR Algorithm

1. Initialize an empty execution ordering $T$.
2. Partition outstanding transactions into buy orders ($B_{buy}$) and sell orders ($B_{sell}$).
3. While both $B_{buy}$ and $B_{sell}$ are non-empty:
    - If current token 1 reserves ≥ initial token 1 reserves:
        - Append any order from $B_{buy}$ to $T$ and remove it from $B_{buy}$.
    - Else:
        - Append any order from $B_{sell}$ to $T$ and remove it from $B_{sell}$.
4. If any orders remain, append them to $T$ in any order.

## Implementation

Our implementation modifies Uniswap V2 to enforce the GSR at the smart contract level. Unlike the original paper's verifier ([Algorithm 4](#algorithm-4-gsr-verifier)), which checks the entire order of transactions from the beginning of the block every time, our approach verifies new transactions in real-time. This results in a constant-time verification algorithm for new transactions, improving efficiency over the linear-time algorithm in the original paper.

The key changes are in the swap function, adding 24 lines of code:

```solidity
function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
    // ... existing swap logic ...

    if (block.number > sequencingRuleInfo.blockNumber) {
        // We have a new block, so we must reset the sequencing rule info.
        // This includes the initial token reserves used in the GSR.
        sequencingRuleInfo.blockNumber = block.number;
        sequencingRuleInfo.reserve0Start = _reserve0;
        sequencingRuleInfo.emptyBuysOrSells = false;
    } else {
        // Determine if this is a buy or sell swap
        SwapType swapType = amount0Out > 0 ? SwapType.BUY : SwapType.SELL;

        if (sequencingRuleInfo.emptyBuysOrSells) {
            // We've entered the "tail" of the ordering. 
            // In the tail, all remaining swaps must be of the same type.
            // This occurs when we've run out of either buy or sell orders.
            // The tailSwapType represents the type of swaps in the tail.
            require(swapType == sequencingRuleInfo.tailSwapType, "UniswapV2: Swap violates GSR");
        } else {
            // Determine the required swap type based on current reserves
            // This implements the core logic of the Greedy Sequencing Rule
            SwapType requiredSwapType = _reserve0 >= sequencingRuleInfo.reserve0Start ? SwapType.SELL : SwapType.BUY;

            if (swapType != requiredSwapType) {
                // If the swap type doesn't match the required type, we've run out of one type of order
                // This means we're entering the tail of the ordering
                sequencingRuleInfo.emptyBuysOrSells = true;
                // The tail swap type is set to the current swap type
                // All subsequent swaps must be of this type
                sequencingRuleInfo.tailSwapType = swapType;
            }
        }
    }

    // ... continue with swap execution ...
}
```
This implementation ensures that the GSR's guarantees are maintained throughout the entire block, even when dealing with an uneven distribution of buy and sell orders. It's computationally efficient and verifiable, allowing anyone to check if the new swap leads to a valid ordering. It does not have any external depedencies, and it does not depend on any off-chain computation, oracles, or additional infrastructure.


## Benefits

- Mitigates sandwich attacks while preserving atomic composability.
- $O(1)$ overhead on the swap function.
- Provides provable execution quality guarantees for users.
- Minimal changes to existing Uniswap V2 contracts.
- Does not rely on trading costs or user-set limit orders.

## Limitations and Future Work

1. While the GSR prevents classic sandwich attacks, it doesn't eliminate all forms of MEV. The paper proves that for any sequencing rule, there exist scenarios where proposers can still obtain risk-free profits ([Theorem 4.2](#theorem-42-existence-of-risk-free-profits)).
2. Multi-block MEV remains a concern. A proposer controlling consecutive blocks could potentially manipulate prices across block boundaries.
These approaches could increase the cost and complexity of such attacks:
    - Updating the initial price less frequently
    - Using a moving average over several past blocks.
3. The current implementation is designed for two-token pools. Extending these guarantees to pools with three or more tokens remains an open question.
4. Further research is needed to characterize optimal sequencing rules that maximize user welfare under strategic proposer behavior.
5. Exploring randomized sequencing rules as a potential avenue for eliminating risk-free profits for proposers.

# Appendix

These were obtained from the original paper, which also contains proofs.

### Theorem 4.2: Existence of Risk-Free Profits

For a class of liquidity pool exchanges (that includes Uniswap), for any sequencing rule, there are instances where the proposer has a profitable risk-free undetectable deviation.

### Theorem 5.1: Duality Theorem
Consider any liquidity pool exchange with potential $\phi$. For any pair of states $X, X' ∈ L_{c}(\phi)$, either:
- any buy order receives a better execution at $X$ than $X'$, or
- any sell order receives a better execution at $X$ than $X'$.

where $L_{c}(\phi)$ is the collection of reachable states with the potential $\phi$.

### Theorem 5.2: Greedy Sequencing Rule (GSR)

We specify a sequencing rule (the Greedy Sequencing Rule) such that, for any valid execution ordering, then for any user transaction $A$ that the proposer includes in the block, it must be that either (1) the user efficiently detects the proposer did not respect the sequencing rule, or (2) the execution price of $A$ for the user is at least as good as if $A$ was the only transaction in the block, or (3) the execution price of $A$ is worse than this standalone price but the proposer does not gain when including $A$ in the block.

### Algorithm 4: GSR Verifier

1. For $t=1,2,\ldots,|T|$:
    1. If $T_{t}, T_{t+1} \ldots, T_{|T|}$ are orders of the same type (i.e., all are buys or all are sells orders), then output $True$.
    2. If $X_{t-1,1} >= X_{0,1}$ and $T_{t}$ is a buy order, then output $False$.
    3. If $X_{t-1,1} <= X_{0,1}$ and $T_{t}$ is a sell order, then output $False$.
    4. Let $X_{t}$ be the state after $T_{t}$ executes on $X_{t-1}$.
2. Output $True$.