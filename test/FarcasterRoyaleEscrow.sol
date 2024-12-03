// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {FarcasterRoyaleEscrow} from "../src/FarcasterRoyaleEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FarcasterRoyaleEscrowTest is Test {
    FarcasterRoyaleEscrow public farcasterRoyaleEscrow;
    IERC20 public usdc;

    address baseMainnet_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address trustedSigner = 0x83aDF05fe9f6B06AaE0Cffe5feAc085B5349E5c8;
    
    // Test addresses
    address challenger = address(1);
    address opponent = address(2);
    address randomUser = address(3);

    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant USDC_INITIAL_BALANCE = 1000e6; // 1000 USDC
    uint256 constant BATTLE_AMOUNT = 1 ether;
    uint256 constant BATTLE_AMOUNT_USDC = 10e6; // 10 USDC

    // Test signature constants
    bytes constant TEST_SIGNATURE = hex"76a4535b1008306afcfe89c0d7271219ada50c18bbbf19fb924a319c325f49266fec3856a9f01afa3e7e60ade8f5184cbec7f4e0414d4cb314b1981ed447855e1c";
    bytes32 constant TEST_MESSAGE_HASH = 0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f;

    event BattleCreated(address indexed challenger, address indexed opponent, uint battleId, uint amount, bool isNative);
    event BattleAccepted(address indexed opponent, uint battleId);
    event BattleResolved(uint battleId, FarcasterRoyaleEscrow.Outcome outcome);
    event BattleCancelled(address indexed challenger);

    function setUp() public {
        farcasterRoyaleEscrow = new FarcasterRoyaleEscrow(trustedSigner, baseMainnet_USDC);
        usdc = IERC20(baseMainnet_USDC);

        // Setup balances
        vm.deal(challenger, INITIAL_BALANCE);
        vm.deal(opponent, INITIAL_BALANCE);
        
        // Setup USDC balances and approvals
        deal(address(usdc), challenger, USDC_INITIAL_BALANCE);
        deal(address(usdc), opponent, USDC_INITIAL_BALANCE);
        
        vm.startPrank(challenger);
        usdc.approve(address(farcasterRoyaleEscrow), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(opponent);
        usdc.approve(address(farcasterRoyaleEscrow), type(uint256).max);
        vm.stopPrank();
    }

    // Test Battle Proposal - Native Token
    function testBattleProposalNative() public {
        vm.startPrank(challenger);
        
        vm.expectEmit(true, true, false, true);
        emit BattleCreated(challenger, opponent, 1, BATTLE_AMOUNT, true);
        
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        (
            address _challenger,
            address _opponent,
            uint _amount,
            bool _claimed,
            bool _isNative,
            FarcasterRoyaleEscrow.Outcome _outcome,
            bool _accepted
        ) = farcasterRoyaleEscrow.s_battles(1);
        
        assertEq(_challenger, challenger);
        assertEq(_opponent, opponent);
        assertEq(_amount, BATTLE_AMOUNT);
        assertEq(_claimed, false);
        assertEq(_isNative, true);
        assertEq(uint(_outcome), uint(FarcasterRoyaleEscrow.Outcome.NONE));
        assertEq(_accepted, false);
        
        vm.stopPrank();
    }

    // Test Battle Proposal - USDC
    function testBattleProposalUSDC() public {
        vm.startPrank(challenger);
        
        uint256 initialBalance = usdc.balanceOf(challenger);
        
        vm.expectEmit(true, true, false, true);
        emit BattleCreated(challenger, opponent, 1, BATTLE_AMOUNT_USDC, false);
        
        farcasterRoyaleEscrow.battleProposal(opponent, BATTLE_AMOUNT_USDC);
        
        assertEq(usdc.balanceOf(challenger), initialBalance - BATTLE_AMOUNT_USDC);
        
        vm.stopPrank();
    }

    // Test Accept Battle - Native Token
    function testAcceptBattleNative() public {
        // Create battle first
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.startPrank(opponent);
        
        vm.expectEmit(true, false, false, true);
        emit BattleAccepted(opponent, 1);
        
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
        
        (,,,,,,bool accepted) = farcasterRoyaleEscrow.s_battles(1);
        assertTrue(accepted);
        
        vm.stopPrank();
    }

    // Test Cancel Battle
    function testCancelBattle() public {
        vm.startPrank(challenger);
        
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        uint256 balanceBefore = challenger.balance;
        
        vm.expectEmit(true, false, false, false);
        emit BattleCancelled(challenger);
        
        farcasterRoyaleEscrow.cancelBattle(1);
        
        assertEq(challenger.balance, balanceBefore + BATTLE_AMOUNT);
        
        // Verify battle is deleted
        (address _challenger,,,,,FarcasterRoyaleEscrow.Outcome _outcome,) = farcasterRoyaleEscrow.s_battles(1);
        assertEq(_challenger, address(0));
        assertEq(uint(_outcome), uint(FarcasterRoyaleEscrow.Outcome.NONE));
        
        vm.stopPrank();
    }

    // Test Claim
    function testClaimWinnerChallenger() public {
        // Setup battle
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.prank(opponent);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
        
        vm.startPrank(challenger);
        uint256 balanceBefore = challenger.balance;
        
        vm.expectEmit(false, false, false, true);
        emit BattleResolved(1, FarcasterRoyaleEscrow.Outcome.CHALLENGER);
        
        farcasterRoyaleEscrow.claim(
            1,
            TEST_MESSAGE_HASH,
            TEST_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.CHALLENGER
        );
        
        // Winner should receive double the amount
        assertEq(challenger.balance, balanceBefore + (BATTLE_AMOUNT * 2));
        
        vm.stopPrank();
    }

    // Test failure cases
    function testFailAcceptBattleNotOpponent() public {
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.prank(randomUser);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
    }

    function testFailCancelAcceptedBattle() public {
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.prank(opponent);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
        
        vm.prank(challenger);
        farcasterRoyaleEscrow.cancelBattle(1);
    }

    function testFailDoubleAccept() public {
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.startPrank(opponent);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
        vm.stopPrank();
    }

    function testFailClaimUnacceptedBattle() public {
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.prank(challenger);
        farcasterRoyaleEscrow.claim(
            1,
            TEST_MESSAGE_HASH,
            TEST_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.CHALLENGER
        );
    }

    function testFailDoubleClaim() public {
        // Setup and accept battle
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.prank(opponent);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
        
        vm.startPrank(challenger);
        farcasterRoyaleEscrow.claim(
            1,
            TEST_MESSAGE_HASH,
            TEST_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.CHALLENGER
        );
        
        farcasterRoyaleEscrow.claim(
            1,
            TEST_MESSAGE_HASH,
            TEST_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.CHALLENGER
        );
        vm.stopPrank();
    }

    // Test signature verification
    function testSignatureVerification() public {
        address recovered = farcasterRoyaleEscrow.recoverSigner(
            TEST_MESSAGE_HASH,
            TEST_SIGNATURE
        );
        assertEq(recovered, trustedSigner);
    }

    function testDrawOutcome() public {
        // Constants for draw test
        bytes memory DRAW_SIGNATURE = hex"38fd86a4965506edc0d73ce6fa9a2b25af2c3dd5d2cbbfe66d404600f817dcaa134c59678136f0db6e61b88727f33f2134690b0ccaa3b4e9729a03b02a09e77d1b";
        bytes32 DRAW_MESSAGE_HASH = 0xa15bc60c955c405d20d9149c709e2460f1c2d9a497496a7f46004d1772c3054c;

        // Setup battle
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponent, 0);
        
        vm.prank(opponent);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(1);
        
        uint256 balanceBefore = challenger.balance;
        
        vm.prank(challenger);
        farcasterRoyaleEscrow.claim(
            1,
            DRAW_MESSAGE_HASH,
            DRAW_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.DRAW
        );
        
        // In draw, should receive only original amount back
        assertEq(challenger.balance, balanceBefore + BATTLE_AMOUNT);
    }
}