# 🥪🦄 Sandwich-Mitigating Uniswap V2

<img src="unicorn.png" width="46%">

> **Background:** Matheus V. X. Ferreira and David C. Parkes. [_Credible Decentralized Exchange Design via Verifiable Sequencing Rules_](https://arxiv.org/pdf/2209.15569).

Uniswap V2 is minimally modified to enforce on swaps a verifiable sequencing rule, the Greedy Sequencing Rule, which makes sandwich attacks unprofitable. This approach preserves atomic composability and requires no additional infrastructure or off-chain computation.

## The Greedy Sequencing Rule (GSR)

The GSR provides strong execution guarantees for users. It leverages a key property of two-token liquidity pools: the Duality Theorem.

> **Theorem 5.1** (Duality Theorem)**.** For any pair of states $X, X'$ in a liquidity pool exchange with potential $\phi$, either: <br>- Any buy order receives a better execution at $X$ than $X'$, or <br>- Any sell order receives a better execution at $X$ than $X'$. 

This theorem forms the foundation for the GSR, which follows this algorithm:

- Execute any buy or any sell order, whichever receives better execution (per Theorem 5.1).
- Continue this process until buys or sells are exhausted.
- Include all remaining swaps in any order.

> **Theorem 5.2** Greedy Sequencing Rule (GSR)**.** We specify a sequencing rule (the Greedy Sequencing Rule) such that, for any valid execution ordering, then for any user transaction $A$ that the proposer includes in the block, it must be one of the following: <br>1. The user efficiently detects the proposer did not respect the sequencing rule. <br>2. The execution price of $A$ is at least as good as if $A$ was the only transaction in the block. <br>3. The execution price of $A$ is worse but the proposer does not gain when including $A$ in the block.

A key assumption is that proposers for contiguous blocks are _not_ controlled by the same party. Weakening this assumption shows how a sandwich attack spanning multiple blocks could be executed. Assume $B_i$ and $B_i+1$ are two contiguous blocks controlled by the same party. The proposer for $B_i$ includes the sandwich's first leg (the transaction front-running the user), followed by the user's swap, at the end of the block. This would not be blocked by the GSR because the third transaction is missing. However, in the next block, the proposer for $B_i+1$ includes the final leg of the sandwich attack, where they profit. They were able to sandwich the user's swap risk-free.

### GSR Algorithm

The GSR relies on a recursive algorithm that takes as input a set of transactions $B$ and the block's initial reserves of token 1 (or token 0) and produces a _valid_ execution ordering $(T_1 , … , T_{|B|})$, a permutation of transactions in $B$.

The algorithm is as follows:

1. Initialize an empty execution ordering $T$.
2. Partition transactions in $B$ into buy orders $B_{buy}$ and sell orders $B_{sell}$.
3. While both $B_{buy}$ and $B_{sell}$ are non-empty:
    - If token 1 reserves currently ≥ token 1 reserves at block start:
        - Append any order from $B_{buy}$ to $T$ and remove it from $B_{buy}$.
    - Else:
        - Append any order from $B_{sell}$ to $T$ and remove it from $B_{sell}$.
4. If any orders remain, append them to $T$ in any order.

## Implementation

This implementation modifies Uniswap V2's smart contracts to enforce the GSR rule on swaps. Unlike the [verifier algorithm in the paper](#ferreira--parkes-2023-gsr-verifier-algorithm), which iterates through the entire execution ordering, the algorithm presented here assumes that the execution ordering before adding a swap is valid. It then validates the new swap in $O(1)$. This leads to a verifier algorithm in $O(1)$, better suited for this implementation than the paper's algorithm in $O(|T|)$.

Additionally, if we used `reserve1` values instead of prices for making comparisons, as in the paper, minting LP positions could make the algorithm unreliable, because `reserve1` doesn't contain information about the other side of the pool that also changes (i.e., `reserve2`). The price, on the other hand, incorporates information about both in the calculation, since `price = reserve1 / reserve2`. Hence, we use `price` instead of `reserve1`.

The key changes are in [`UniswapV2Pair`](src/UniswapV2Pair.sol)'s swap function. If a swap would lead to an invalid order according to the GSR, the transaction reverts.

<details open>
<summary>Solidity</summary>

```solidity
uint136 public lastSequencedBlockNumber;
uint112 public blockPriceStart; // price at the start of the block
uint8 public blockTailSwapType; // 0 for none, 1 for buy, 2 for sell

function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
    // ... existing swap logic ...

    // compute the current price with 1e6 decimals (1e18 can easily overflow)
    uint112 price = (_reserve1 * 1e6) / _reserve0;

    // check if the sequencing rule info has been initialized for this block
    if (block.number != lastSequencedBlockNumber) {
        // if not, initialize it with the current price as the start price
        lastSequencedBlockNumber = uint136(block.number);
        blockPriceStart = price;
        blockTailSwapType = 0; // no tail swaps yet
    } else {
        // we want to determine the swap type.
        // we follow the same type as blockTailSwapType, which is a uint8
        // where 0 = none, 1 = buy, 2 = sell, so that we can compare the
        // swap type against blockTailSwapType later without converting
        // between uint8 and bool.
        uint8 swapType = amount0Out > 0 ? 1 : 2; // 1 for buy, 2 for sell

        // check if we are not in the "tail" of the ordering (Definition 5.2).
        if (blockTailSwapType == 0) {
            // determine the required swap type based on the current price 
            // and the price at the start of the block.
            // this implements the core logic of the Greedy Sequencing Rule.
            // we follow the same type as blockTailSwapType: uint8.
            uint8 swapTypeExpected = price >= blockPriceStart ? 1 : 2;

            if (swapType != swapTypeExpected) {
                // if the swap type doesn't match the required type, we've
                // run out of at least one type of order.
                // the tail swap type is set to the current swap type
                blockTailSwapType = swapType;
            }
        } else {
            // we've entered the "tail" of the ordering (Definition 5.2).
            // in the tail, all remaining swaps must be of the same type (Lemma 5.1).
            // this occurs when we've run out of either buy or sell orders.
            // blockTailSwapType stores the type of swaps in the tail.
            require(swapType == blockTailSwapType, "UniswapV2: VIOLATES_GSR");
        }
    }

    // ... continue with swap execution ...
}
```
</details>

This implementation ensures that the GSR's guarantees are maintained throughout the entire block, even when dealing with an uneven distribution of buy and sell orders. It's computationally efficient and verifiable, allowing anyone to check if the new swap leads to a valid ordering. It does not have any external dependencies, and it does not depend on any off-chain computation, oracles, or additional infrastructure.

### Gas Cost

These gas reports were done with the optimizer enabled, 999,999 runs, and Solidity version 0.8.23.

#### Without changes

| UniswapV2Pair contract |       |        |        |        |         |
|------------------------|-------|--------|--------|--------|---------|
| Function Name          | min   | avg    | median | max    | # calls |
| swap                   | 64354 | 64365  | 64374  | 64374  | 26      |

#### With changes

| UniswapV2Pair contract |       |        |        |        |         |
|------------------------|-------|--------|--------|--------|---------|
| Function Name          | min   | avg    | median | max    | # calls |
| swap                   | 67092 | 73799  | 70025  | 86945  | 26      |

The following table shows the difference in gas costs before and after the changes.

| $\Delta$      |        |         |        |         |
|---------------|--------|---------|--------|---------|
| Function Name | min    | avg     | median | max     |
| swap          | +4.25% | +14.66% | +8.78% | +35.06% |

It's important to note that while it has increased, the gas cost of the swap function may be largely offset by the value saved from sandwich attacks. This is because the two are independent.

## How does this prevent sandwich attacks?

Consider the following example, where $T$ is an execution ordering over swaps in the same block for a [`UniswapV2Pair`](src/UniswapV2Pair.sol) instance:
1. The builder includes the swap for the first side of the sandwich attack (a buy order) as $T_1$, to front-run the user's swap.
2. Then, it includes the user's swap (a buy order) as $T_2$.
    - The algorithm recognizes that any sell order would have received a better execution than another buy order.
    - Therefore, the algorithm assumes that the builder must have run out of sell orders, so the builder is restricted to only include buy orders for the remainder of the block, starting at $T_3$.
3. The builder tries to include the swap for the final side of the sandwich attack (a sell order) as $T_3$, but the transaction reverts.
    - The order is not a buy order, as restricted by the GSR.

## Benefits

- Mitigates sandwich attacks while preserving atomic composability.
- $O(1)$ overhead on the swap function.
- Provides provable execution quality guarantees for users.
- Minimal changes to existing Uniswap V2 contracts.
- Does not rely on trading costs or user-set limit orders.
- Does not require any additional infrastructure or off-chain computation.

## Limitations and Future Work

1. While the GSR prevents classic sandwich attacks, it doesn't eliminate all forms of MEV. The paper [_Credible Decentralized Exchange Design via Verifiable Sequencing Rules_](https://arxiv.org/pdf/2209.15569) proves that for any sequencing rule, there exist scenarios where proposers (builders) can still obtain risk-free profits.

> **Theorem 4.2.** For a class of liquidity pool exchanges (that includes Uniswap), for any sequencing rule, there are instances where the proposer has a profitable risk-free undetectable deviation.

2. The builder needs to follow the [GSR algorithm](#gsr-algorithm) to obtain several valid swaps in the same block. In the simplest terms, for a new block, they have to include buys and sells in alternating order until they run out of either. After that, they get to include the remaining in any order.
    - Would it be unfeasible to include orders in alternating order while subscribing to priority ordering?
3. As the paper [_MEV Makes Everyone Happy under Greedy Sequencing Rule_](https://arxiv.org/pdf/2309.12640) shows, when there is no trading fee, a polynomial time algorithm for a proposer to compute an optimal strategy is given. However, when trading fees aren't zero, it is NP-hard to find an optimal strategy. This means that, in practice, builders may not have the computational resources to always find the optimal strategy.
4. Multi-block MEV remains a concern. A builder controlling consecutive blocks could potentially implement a sandwich attack spanning several blocks risk-free, circumventing the GSR.
5. Pools implementing the GSR seem to have price discovery issues when there are 3 or more pools for the same asset.

# Appendix

### Ferreira & Parkes (2023) GSR Verifier Algorithm

It outputs $True$ or $False$, and proceeds as follows:

1. For $t=1,2,…,|T|$:
    1. If $T_{t}, T_{t+1} …, T_{|T|}$ are orders of the same type (i.e., all are buys or all are sells orders), then output $True$.
    2. If $X_{t-1,1} \ge X_{0,1}$ and $T_{t}$ is a buy order, then output $False$.
    3. If $X_{t-1,1} < X_{0,1}$ and $T_{t}$ is a sell order, then output $False$.
    4. Let $X_{t}$ be the state after $T_{t}$ executes on $X_{t-1}$.
2. Output $True$.
