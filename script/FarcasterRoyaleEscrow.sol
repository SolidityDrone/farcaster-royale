// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {FarcasterRoyaleEscrow} from "../src/FarcasterRoyaleEscrow.sol";

contract CounterScript is Script {
    FarcasterRoyaleEscrow public farcasterRoyaleEscrow;

    address baseMainnet_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address trustedSigner = 0x83aDF05fe9f6B06AaE0Cffe5feAc085B5349E5c8;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        farcasterRoyaleEscrow = new FarcasterRoyaleEscrow(trustedSigner, baseMainnet_USDC);

        vm.stopBroadcast();
    }
}
