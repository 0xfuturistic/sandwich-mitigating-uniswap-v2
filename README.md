# 🥪🦄 Sandwich-Mitigating Uniswap V2

<img src="unicorn.png" width="46%">

> **Background:** Matheus V. X. Ferreira and David C. Parkes. _Credible Decentralized Exchange Design via Verifiable Sequencing Rules._ URL: https://arxiv.org/pdf/2209.15569.

Uniswap V2 is minimally modified to enforce a verifiable sequencing, the Greedy Sequencing Rule, which makes sandwich attacks unprofitable. This approach preserves atomic composability and requires no additional infrastructure or off-chain computation. 

## The Greedy Sequencing Rule (GSR)

The GSR provides strong execution guarantees for users. It leverages a key property of two-token liquidity pools: the Duality Theorem.

> **Theorem 5.1** (Duality Theorem)**.** For any pair of states $X, X'$ in a liquidity pool exchange with potential $\phi$, either: <br>- Any buy orders receives a better execution at $X$ than $X'$, or <br>- Any sell orders receives a better execution at $X$ than $X'$. 

This theorem forms the foundation of the GSR, which operates as follows:

- Execute the type of order (buy or sell) that's getting the better price.
- Continue this process until one type of order is exhausted.
- Once one type is exhausted, only allow the other type for the rest of the block.

By following these rules, the GSR ensures the following:

> **Theorem 5.2** Greedy Sequencing Rule (GSR)**.** We specify a sequencing rule (the Greedy Sequencing Rule) such that, for any valid execution ordering, then for any user transaction $A$ that the proposer includes in the block, it must be one of the following: <br>1. The user efficiently detects the proposer did not respect the sequencing rule. <br>2. The execution price of $A$ is at least as good as if $A$ was the only transaction in the block. <br>3. The execution price of $A$ is worse but the proposer does not gain when including $A$ in the block.

A key assumption is that proposers for contiguous blocks are _not_ controlled by the same party. Weakening this assumption shows how a sandwich attack spanning multiple blocks could be executed. Assume $B_i$ and $B_i+1$ are two contiguous blocks controlled by the same party. The proposer for $B_i$ includes the user's transaction $A$ and the sandwich's first leg (the transaction front-running the user) at the end of the block. Then, in the next block, the proposer for $B_i+1$ includes the final transaction of the sandwich attack, in the opposite direction, at the top of the block. This is would be a valid execution ordering, yet the user's transaction $A$ is successfully sandwich-attacked.

### GSR Algorithm

The GSR relies on a recursive algorithm that takes as input a set of transactions $B$ and the block's initial reserves of token 1 (or 0) and produces a _valid_ execution ordering $(T_1 , … , T_{|B|})$, a permutation of transactions in $B$.

The algorithm is as follows:

1. Initialize an empty execution ordering $T$.
2. Partition transactions in $B$ into buy orders ($B_{buy}$) and sell orders ($B_{sell}$).
3. While both $B_{buy}$ and $B_{sell}$ are non-empty:
    - If current token 1 reserves ≥ initial token 1 reserves:
        - Append any order from $B_{buy}$ to $T$ and remove it from $B_{buy}$.
    - Else:
        - Append any order from $B_{sell}$ to $T$ and remove it from $B_{sell}$.
4. If any orders remain, append them to $T$ in any order.

## Implementation

This implementation modifies Uniswap V2's smart contracts to enforce the GSR rule on swaps. Unlike the [verifier algorithm in the paper](#ferreira--parkes-2023-gsr-verifier-algorithm), which iterates through the entire execution ordering, our algorithm assumes that the execution ordering before adding a swap is valid, and then just validates the new swap in $O(1)$. This leads to a verifier algorithm in $O(1)$, better suited for this implementation than the paper's algorithm in $O(|T|)$.

The key changes are in [`UniswapV2Pair`](src/UniswapV2Pair.sol)'s swap function. If a swap violates the GSR, the transaction reverts.

```solidity
uint136 public lastSequencedBlock;
uint112 public blockPriceStart;
uint8 public blockTailSwapType;

function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
    // ... existing swap logic ...

    // compute the current price with 1e6 decimals (1e18 can easily overflow)
    uint112 price = (_reserve1 * 1e6) / _reserve0;

    // check if the sequencing rule info has been initialized for this block
    if (block.number != lastSequencedBlock) {
        // if not, initialize it with the current price as the start price
        lastSequencedBlock = uint136(block.number);
        blockPriceStart = price;
    } else {
        // Determine if this is a buy or sell swap
        uint8 swapType = amount1Out > 0 ? 1 : 2; // 1 for buy, 2 for sell

        if (blockTailSwapType != 0) {
            // We've entered the "tail" of the ordering (Definition 5.2).
            // In the tail, all remaining swaps must be of the same type (Lemma 5.1).
            // This occurs when we've run out of either buy or sell orders.
            // The tailSwapType represents the type of swaps in the tail.
            require(swapType == blockTailSwapType, "UniswapV2: VIOLATES_GSR");
        } else {
            // Determine the required swap type based on current reserves
            // This implements the core logic of the Greedy Sequencing Rule
            uint8 swapTypeExpected = price < blockPriceStart ? 1 : 2;

            if (swapType != swapTypeExpected) {
                // If the swap type doesn't match the required type, we've run out of one type of order
                // This means we're entering the tail of the ordering

                // The tail swap type is set to the current swap type
                // All subsequent swaps must be of this type
                blockTailSwapType = swapType;
            }
        }
    }

    // ... continue with swap execution ...
}
```

If we used `reserve1` values instead prices for making comparisons, as in the paper, minting LP positions could make the algorithm unreliable, because `reserves1` doesn't contain information about the other side of the pool that also changes (i.e., `reserves2`). The price, on the other hand, incorporates information about both in the calculation, since `price = reserve1 / reserve2`. Hence, it is a better measure.

This implementation ensures that the GSR's guarantees are maintained throughout the entire block, even when dealing with an uneven distribution of buy and sell orders. It's computationally efficient and verifiable, allowing anyone to check if the new swap leads to a valid ordering. It does not have any external dependencies, and it does not depend on any off-chain computation, oracles, or additional infrastructure.

### Gas Cost

This gas report was done with the optimizer enabled, 999,999 runs, and Solidity version 0.8.23.

#### Pre-changes

| UniswapV2Pair contract |       |        |        |        |         |
|------------------------|-------|--------|--------|--------|---------|
| Function Name          | min   | avg    | median | max    | # calls |
| swap                   | 64354 | 64365  | 64374  | 64374  | 26      |

#### Post-changes

| UniswapV2Pair contract |       |        |        |        |         |
|------------------------|-------|--------|--------|--------|---------|
| Function Name          | min   | avg    | median | max    | # calls |
| swap                   | 67043 | 73734  | 69953  | 86879  | 26      |

The following table shows the difference in gas costs before and after the changes.

| $\Delta$      |        |         |        |         |
|---------------|--------|---------|--------|---------|
| Function Name | min    | avg     | median | max     |
| swap          | +4.18% | +14.56% | +8.67% | +34.96% |

It's important to note that while it has increased, the gas cost of the swap function may be largely offset by value saved from sandwich attacks. This is because the two are independent.

## How does this prevent sandwich attacks?

Consider the following example, where $T$ is an execution ordering over swaps in the same block for a [`UniswapV2Pair`](src/UniswapV2Pair.sol) instance:
1. The proposer exexcutes the swap for the first side of the sandwich attack (a buy order) as $T_1$.
2. Then, it executes the user's swap (a buy order) as $T_2$.
    - The algorithm recognizes that the swap type that would have received a better execution price at $X$ than $X'$ was a sell order instead of another buy order.
    - Therefore, the algorithm assumes that the proposer must have run out of sell orders, so it binds the proposer to only include buy orders for the remainder of the block, the tail, starting from $T_2$.
3. The proposer tries to execute the swap for the final side of the sandwich attack (a sell order) as $T_3$ but fails.
    - The order type (sell) would be blocked by the GSR because the GSR requires that the swap type be buy for orders in the tail, which is where $T_3$ belongs to as it follows $T_2$.

## Benefits

- Mitigates sandwich attacks while preserving atomic composability.
- $O(1)$ overhead on the swap function.
- Provides provable execution quality guarantees for users.
- Minimal changes to existing Uniswap V2 contracts.
- Does not rely on trading costs or user-set limit orders.

## Limitations and Future Work

1. While the GSR prevents classic sandwich attacks, it doesn't eliminate all forms of MEV. The paper proves that for any sequencing rule, there exist scenarios where proposers can still obtain risk-free profits:

> **Theorem 4.2.** For a class of liquidity pool exchanges (that includes Uniswap), for any sequencing rule, there are instances where the proposer has a profitable risk-free undetectable deviation.

2. The proposer needs to follow the [GSR algorithm](#gsr-algorithm), taking as set of transactions the swaps in the same block for a [`UniswapV2Pair`](src/UniswapV2Pair.sol) instance. Concretely, they'd take a set of swaps $B$ and an initial state $X_0$ (denoting the state before a swap in this block executes on the chain), and recursively construct an execution ordering $(T_1 , … , T_{|B|})$ (a permutation of the swaps in $B$). 
As the paper [_MEV Makes Everyone Happy under Greedy Sequencing Rule_](https://arxiv.org/pdf/2309.12640) shows, when there is no trading fee, a polynomial time algorithm for a proposer to compute an optimal strategy is given. However, when trading fees aren't zero, it is NP-hard to find an optimal strategy.

3. Multi-block MEV remains a concern. A proposer controlling consecutive blocks could potentially manipulate prices across block boundaries. Nevertheless, the cost and complexity of such attacks could be increased by:
    - Updating the initial price less frequently.
    - Using a moving average over several past blocks.
4. Further research is needed to characterize optimal sequencing rules that maximize user welfare under strategic proposer behavior.
5. The GSR has price discovery issues (i.e., when there are three different pools for the same asset).

# Appendix

### Ferreira & Parkes (2023) GSR Verifier Algorithm

It outputs $True$ or $False$, and proceeds as follows:

1. For $t=1,2,…,|T|$:
    1. If $T_{t}, T_{t+1} …, T_{|T|}$ are orders of the same type (i.e., all are buys or all are sells orders), then output $True$.
    2. If $X_{t-1,1} \ge X_{0,1}$ and $T_{t}$ is a buy order, then output $False$.
    3. If $X_{t-1,1} < X_{0,1}$ and $T_{t}$ is a sell order, then output $False$.
    4. Let $X_{t}$ be the state after $T_{t}$ executes on $X_{t-1}$.
2. Output $True$.
