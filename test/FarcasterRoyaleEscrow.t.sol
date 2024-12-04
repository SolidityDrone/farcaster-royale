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
    address opponent1 = address(2);
    address opponent2 = address(3);
    address opponent3 = address(4);
    address randomUser = address(5);

    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant USDC_INITIAL_BALANCE = 1000e6; // 1000 USDC
    uint256 constant BATTLE_AMOUNT = 1 ether;
    uint256 constant BATTLE_AMOUNT_USDC = 10e6; // 10 USDC
    uint256 constant BATTLE_ID = 1;

    // Battle proposal signature constants
    bytes constant BATTLE_PROPOSAL_SIGNATURE = hex"69837299be9f7700fc2584a0d06e23c8eecd0205574668e98cde2248f4e537a139e5a2ab83232dc44e50e368cc273773d402e82fa08b99a196be3c1cc7524e711b";
    bytes32 constant BATTLE_PROPOSAL_HASH = 0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6;

    // Other signature constants remain the same
    bytes constant CHALLENGER_SIGNATURE = hex"76a4535b1008306afcfe89c0d7271219ada50c18bbbf19fb924a319c325f49266fec3856a9f01afa3e7e60ade8f5184cbec7f4e0414d4cb314b1981ed447855e1c";
    bytes32 constant CHALLENGER_MESSAGE_HASH = 0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f;
    bytes constant DRAW_SIGNATURE =  hex"38fd86a4965506edc0d73ce6fa9a2b25af2c3dd5d2cbbfe66d404600f817dcaa134c59678136f0db6e61b88727f33f2134690b0ccaa3b4e9729a03b02a09e77d1b";
    bytes32 constant DRAW_MESSAGE_HASH = 0xa15bc60c955c405d20d9149c709e2460f1c2d9a497496a7f46004d1772c3054c;
    bytes constant OPPONENT_SIGNATURE = hex"8f30dda657a70855a4df18b197dd7b69746571667847e60fd9280331f93f23856fb04edee6daac716c67ad0ca9cb4bce938caaaba5cf03055d6d4f88f3f0ba761c";
    bytes32 constant OPPONENT_MESSAGE_HASH = 0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0;

    event BattleCreated(address indexed challenger, address[] indexed opponent, uint battleId, uint amount, bool isNative);
    event BattleAccepted(address indexed opponent, uint battleId);
    event BattleResolved(uint battleId, FarcasterRoyaleEscrow.Outcome outcome);
    event BattleCancelled(address indexed challenger);

    function setUp() public {
        farcasterRoyaleEscrow = new FarcasterRoyaleEscrow(trustedSigner, baseMainnet_USDC);
        usdc = IERC20(baseMainnet_USDC);

        // Setup balances
        vm.deal(challenger, INITIAL_BALANCE);
        vm.deal(opponent1, INITIAL_BALANCE);
        vm.deal(opponent2, INITIAL_BALANCE);
        vm.deal(opponent3, INITIAL_BALANCE);
        
        // Setup USDC balances and approvals
        deal(address(usdc), challenger, USDC_INITIAL_BALANCE);
        deal(address(usdc), opponent1, USDC_INITIAL_BALANCE);
        deal(address(usdc), opponent2, USDC_INITIAL_BALANCE);
        deal(address(usdc), opponent3, USDC_INITIAL_BALANCE);
        
        vm.startPrank(challenger);
        usdc.approve(address(farcasterRoyaleEscrow), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(opponent1);
        usdc.approve(address(farcasterRoyaleEscrow), type(uint256).max);
        vm.stopPrank();
    }

    function testBattleProposalNative() public {
        address[] memory opponents = new address[](2);
        opponents[0] = opponent1;
        opponents[1] = opponent2;

        vm.startPrank(challenger);
        
        vm.expectEmit(true, true, false, true);
        emit BattleCreated(challenger, opponents, BATTLE_ID, BATTLE_AMOUNT, true);
        
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(
            opponents,
            0,
            BATTLE_ID,
            BATTLE_PROPOSAL_HASH,
            BATTLE_PROPOSAL_SIGNATURE
        );
        
        (
            address _challenger,
            address[] memory _opponents,
            uint _amount,
            bool _claimed,
            bool _isNative,
            FarcasterRoyaleEscrow.Outcome _outcome,
            bool _accepted
        ) = farcasterRoyaleEscrow.getBattle(BATTLE_ID);
        
        assertEq(_challenger, challenger);
        assertEq(_opponents.length, 2);
        assertEq(_opponents[0], opponent1);
        assertEq(_opponents[1], opponent2);
        assertEq(_amount, BATTLE_AMOUNT);
        assertEq(_claimed, false);
        assertEq(_isNative, true);
        assertEq(uint(_outcome), uint(FarcasterRoyaleEscrow.Outcome.NONE));
        assertEq(_accepted, false);
        
        vm.stopPrank();
    }

    function testBattleProposalUSDC() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        vm.startPrank(challenger);
        
        uint256 initialBalance = usdc.balanceOf(challenger);
        
        vm.expectEmit(true, true, false, true);
        emit BattleCreated(challenger, opponents, BATTLE_ID, BATTLE_AMOUNT_USDC, false);
        
        farcasterRoyaleEscrow.battleProposal(
            opponents,
            BATTLE_AMOUNT_USDC,
            BATTLE_ID,
            BATTLE_PROPOSAL_HASH,
            BATTLE_PROPOSAL_SIGNATURE
        );
        
        assertEq(usdc.balanceOf(challenger), initialBalance - BATTLE_AMOUNT_USDC);
        
        vm.stopPrank();
    }

    function testFailInvalidSignature() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        bytes memory invalidSignature = hex"1234567890";
        
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal(
            opponents,
            BATTLE_AMOUNT_USDC,
            BATTLE_ID,
            BATTLE_PROPOSAL_HASH,
            invalidSignature
        );
    }

    function testFailBattleIdAlreadyExists() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        vm.startPrank(challenger);
        
        // First proposal
        farcasterRoyaleEscrow.battleProposal(
            opponents,
            BATTLE_AMOUNT_USDC,
            BATTLE_ID,
            BATTLE_PROPOSAL_HASH,
            BATTLE_PROPOSAL_SIGNATURE
        );
        
        // Should fail on second proposal with same battleId
        farcasterRoyaleEscrow.battleProposal(
            opponents,
            BATTLE_AMOUNT_USDC,
            BATTLE_ID,
            BATTLE_PROPOSAL_HASH,
            BATTLE_PROPOSAL_SIGNATURE
        );
        
        vm.stopPrank();
    }
    function testAcceptBattleNative() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        // Create battle first
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        vm.startPrank(opponent1);
        
        vm.expectEmit(true, false, false, true);
        emit BattleAccepted(opponent1, 1);
        
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(BATTLE_ID);
        
        (, , , , , , bool accepted) = farcasterRoyaleEscrow.getBattle(1);
        assertTrue(accepted);
        
        vm.stopPrank();
    }

    function testCancelBattle() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        vm.startPrank(challenger);
        
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        uint256 balanceBefore = challenger.balance;
        
        vm.expectEmit(true, false, false, false);
        emit BattleCancelled(challenger);
        
        farcasterRoyaleEscrow.cancelBattle(1);
        
        assertEq(challenger.balance, balanceBefore + BATTLE_AMOUNT);
        
        // Verify battle is deleted
        (address _challenger, , , , , FarcasterRoyaleEscrow.Outcome _outcome, ) = farcasterRoyaleEscrow.getBattle(1);
        assertEq(_challenger, address(0));
        assertEq(uint(_outcome), uint(FarcasterRoyaleEscrow.Outcome.NONE));
        
        vm.stopPrank();
    }

    function testClaimWinnerChallenger() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        // Setup battle
        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        vm.prank(opponent1);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(BATTLE_ID);
        
        vm.startPrank(challenger);
        uint256 balanceBefore = challenger.balance;
        
        vm.expectEmit(false, false, false, true);
        emit BattleResolved(1, FarcasterRoyaleEscrow.Outcome.CHALLENGER);
        
        farcasterRoyaleEscrow.claim(
            BATTLE_ID,
            CHALLENGER_MESSAGE_HASH,
            CHALLENGER_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.CHALLENGER
        );
        
        // Winner should receive double the amount
        assertEq(challenger.balance, balanceBefore + (BATTLE_AMOUNT * 2));
        
        vm.stopPrank();
    }

    function testClaimWinnerOpponent() public {
        address[] memory opponents = new address[](2);
        opponents[0] = opponent1;
        opponents[1] = opponent2;

        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        vm.prank(opponent1);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(BATTLE_ID);
        
        uint256 balanceBefore = opponent1.balance;
        

        vm.prank(opponent1);
        farcasterRoyaleEscrow.claim(
            BATTLE_ID,
            OPPONENT_MESSAGE_HASH,
            OPPONENT_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.OPPONENT
        );
        
        assertEq(opponent1.balance, balanceBefore + (BATTLE_AMOUNT * 2));
    }

    function testDrawOutcome() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        vm.prank(opponent1);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(BATTLE_ID);
        
        uint256 challengerBalanceBefore = challenger.balance;
        uint256 opponentBalanceBefore = opponent1.balance;
        
        vm.prank(challenger);
        farcasterRoyaleEscrow.claim(
            BATTLE_ID,
            DRAW_MESSAGE_HASH,
            DRAW_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.DRAW
        );
        
        // Both parties should receive their original amount back
        assertEq(challenger.balance, challengerBalanceBefore + BATTLE_AMOUNT);
        assertEq(opponent1.balance, opponentBalanceBefore + BATTLE_AMOUNT);
    }

    function testFailBattleProposalToSelf() public {
        address[] memory opponents = new address[](1);
        opponents[0] = challenger;

        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
    }

    function testFailAcceptBattleNotOpponent() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        vm.prank(randomUser);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(BATTLE_ID);
    }

    function testFailAcceptBattleTwice() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        vm.startPrank(opponent1);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(BATTLE_ID);
        farcasterRoyaleEscrow.acceptBattle{value: BATTLE_AMOUNT}(BATTLE_ID);
        vm.stopPrank();
    }

    function testFailClaimUnacceptedBattle() public {
        address[] memory opponents = new address[](1);
        opponents[0] = opponent1;

        vm.prank(challenger);
        farcasterRoyaleEscrow.battleProposal{value: BATTLE_AMOUNT}(opponents, 0, BATTLE_ID, BATTLE_PROPOSAL_HASH, BATTLE_PROPOSAL_SIGNATURE);
        
        vm.prank(challenger);
        farcasterRoyaleEscrow.claim(
            BATTLE_ID,
            CHALLENGER_MESSAGE_HASH,
            CHALLENGER_SIGNATURE,
            FarcasterRoyaleEscrow.Outcome.CHALLENGER
        );
    }
}