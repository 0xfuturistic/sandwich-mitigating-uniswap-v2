// SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.2;

import "forge-std/Test.sol";
import "src/UniswapV2Factory.sol";
import "src/UniswapV2Pair.sol";
import "src/libraries/UQ112x112.sol";
import "test/mocks/ERC20Mintable.sol";

contract SandwichResistanceTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV2Pair pair;

    function setUp() public {
        token0 = new ERC20Mintable("Token A", "TKNA");
        token1 = new ERC20Mintable("Token B", "TKNB");

        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = UniswapV2Pair(pairAddress);

        token0.mint(10 ether, address(this));
        token1.mint(10 ether, address(this));

        token0.transfer(address(pair), 5 ether);
        token1.transfer(address(pair), 5 ether);

        pair.mint(address(this));
    }

    function test_simpleSandwich_fails() public {
        // first buy
        token1.transfer(address(pair), 1 ether);
        pair.swap(0.99 ether, 0, address(this), "");

        // second buy
        token0.transfer(address(pair), 1 ether);
        pair.swap(0.83 ether, 0, address(this), "");

        // sell
        token0.transfer(address(pair), 1 ether);
        vm.expectRevert("UniswapV2: Swap violates sequencing rule");
        pair.swap(0, 0.99 ether, address(this), "");
    }

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
        vm.expectRevert("UniswapV2: Swap violates sequencing rule");
        pair.swap(0, 0.99 ether, address(this), "");
    }
}
