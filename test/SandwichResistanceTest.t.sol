// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/UniswapV2Pair.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";

/// @title Tests for the sandwich resistance implementation
contract SandwichResistanceTest is Test {
    ERC20Mock token0;
    ERC20Mock token1;
    UniswapV2Pair pair;

    /// @notice Sets up
    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();

        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        pair = UniswapV2Pair(factory.createPair(address(token0), address(token1)));

        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        token0.transfer(address(pair), 5 ether);
        token1.transfer(address(pair), 5 ether);
        pair.mint(address(this));
    }

    /// @notice Tests a simple sandwich attack
    function test_simpleSandwich_fails() public {
        // first buy
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // second buy
        token0.transfer(address(pair), 1 ether);
        pair.swap(0.83 ether, 0, address(this), "");

        // sell
        token0.transfer(address(pair), 1 ether);
        vm.expectRevert("UniswapV2: Swap violates GSR");
        pair.swap(0, 0.99 ether, address(this), "");
    }

    /// @notice Tests a complex sandwich attack
    function test_complexSandwich_fails() public {
        // first buy
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // sell
        token0.transfer(address(pair), 1 ether);
        pair.swap(0, 0.99 ether, address(this), "");

        // second buy
        token0.transfer(address(pair), 1 ether);
        pair.swap(0.83 ether, 0, address(this), "");

        // third buy
        token0.transfer(address(pair), 1 ether);
        pair.swap(0.59 ether, 0, address(this), "");

        // sell
        token0.transfer(address(pair), 1 ether);
        vm.expectRevert("UniswapV2: Swap violates GSR");
        pair.swap(0, 0.99 ether, address(this), "");
    }

    /// @notice Tests for empty buys in the same block
    function test_emptyBuy_succeeds() public {
        // first buy
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // second buy in the same block
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.83 ether, 0, address(this), "");

        // third buy in the same block
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.59 ether, 0, address(this), "");
    }

    /// @notice Tests for empty sells in the same block
    function test_emptySells_succeeds() public {
        // first sell
        token0.transfer(address(pair), 1 ether);
        pair.swap(0, 0.99 ether, address(this), "");

        // second sell in the same block
        token0.transfer(address(pair), 1 ether);
        pair.swap(0, 0.83 ether, address(this), "");

        // third sell in the same block
        token1.transfer(address(pair), 1 ether);
        pair.swap(0, 0.59 ether, address(this), "");
    }

    /// @notice Tests for correct handling of block transition
    function test_blockTransition_succeeds() public {
        // first buy in block N
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // move to next block N+1
        vm.roll(block.number + 1);

        // sell in block N+1
        token0.transfer(address(pair), 1 ether);
        pair.swap(0, 0.99 ether, address(this), "");

        // move to next block
        vm.roll(block.number + 1);

        // buy in block N+2
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // sell in block N+1
        token0.transfer(address(pair), 1 ether);
        pair.swap(0, 0.99 ether, address(this), "");
    }

    /// @notice Tests a sandwich attack in the next block
    function test_simpleSandwich_nextBlock_fails() public {
        // first buy in block N
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // second buy in block N
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // move to next block N+1
        vm.roll(block.number + 1);

        // first buy in block N+1
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // second buy in block N+1
        token0.transfer(address(pair), 1 ether);
        pair.swap(0.83 ether, 0, address(this), "");

        // sell in block N+1 should lead to a sandwich
        token0.transfer(address(pair), 1 ether);
        vm.expectRevert("UniswapV2: Swap violates GSR");
        pair.swap(0, 0.99 ether, address(this), "");
    }
}
