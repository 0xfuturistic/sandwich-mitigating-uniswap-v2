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

    function test_simpleSandwich_fails(uint256) public {
        // first buy
        token1.transfer(address(pair), getPrice() * 1 ether);
        // the denominator is 0.95 because of fees
        pair.swap(0.95 ether / getPrice(), 0, address(this), "");

        // second buy
        pair.swap(0.95 ether / getPrice(), 0, address(this), "");

        // sell
    }

    function test_complexSandwich_fails() public {
        // first buy
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0.09 ether, 0, address(this), "");

        // sell
        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0, 0.09 ether, address(this), "");

        // second buy
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0.09 ether, 0, address(this), "");

        // third buy
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0.09 ether, 0, address(this), "");

        // sell
        token0.transfer(address(pair), 0.1 ether);
        vm.expectRevert("UniswapV2: Swap violates sequencing rule");
        pair.swap(0, 0.09 ether, address(this), "");
    }

    function test_emptySells_succeeds() public {
        // first buy
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0.09 ether, 0, address(this), "");

        // sell
        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0, 0.09 ether, address(this), "");

        // second buy
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0.09 ether, 0, address(this), "");

        // third buy
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0.09 ether, 0, address(this), "");
    }

    function getPrice() public view returns (uint256) {
        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();
        return _reserve1 / _reserve0;
    }
}
