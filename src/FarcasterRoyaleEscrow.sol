// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title FarcasterRoyaleEscrow
/// @author Not Drone
/// @notice A contract for handling Battle Royale style competitions with escrow functionality
/// @dev Implements battle proposal, acceptance, and resolution with both native token and USDC support
contract FarcasterRoyaleEscrow {
    
    /// @notice Emitted when a new battle is created
    /// @param challenger Address of the player creating the battle
    /// @param opponent Address of the challenged player
    /// @param battleId Unique identifier for the battle
    /// @param amount The amount of tokens/ETH wagered
    /// @param isNative True if using native token (ETH), false if using USDC
    event BattleCreated(address indexed challenger, address[] indexed opponent, uint battleId, uint amount, bool isNative);

    /// @notice Emitted when an opponent accepts a battle
    /// @param opponent Address of the accepting player
    /// @param battleId Unique identifier for the accepted battle
    event BattleAccepted(address indexed opponent, uint battleId);

    /// @notice Emitted when a battle is resolved
    /// @param battleId Unique identifier for the resolved battle
    /// @param outcome Result of the battle (CHALLENGER, OPPONENT, or DRAW)
    event BattleResolved(uint battleId, Outcome outcome);

    /// @notice Emitted when a battle is cancelled
    /// @param challenger Address of the player who cancelled their battle
    event BattleCancelled(address indexed challenger);

    /// @notice Counter for generating unique battle IDs
    uint public battleCounter = 1;
    
    /// @notice Address authorized to sign battle outcomes
    address public trustedSigner;
    
    /// @notice Reference to the USDC token contract
    IERC20 public usdc;

    /// @notice Mapping from battle ID to Battle struct
    mapping(uint => Battle) public s_battles;

    /// @notice Possible outcomes for a battle
    /// @dev NONE is the default state before resolution
    enum Outcome { NONE, CHALLENGER, OPPONENT, DRAW }

    /// @notice Structure containing battle details
    /// @dev All battles are stored in the s_battles mapping
    struct Battle {
        address challenger;             // Address of the player who created the battle
        address[] opponentAddresses;    // Addresses of the challenged player
        uint amount;                    // Amount of tokens/ETH wagered
        bool claimed;                   // Whether the prize has been claimed
        bool isNative;                  // True if using native token (ETH)
        Outcome outcome;                // Result of the battle
        bool accepted;                  // Whether the opponent has accepted
    }

    /// @notice Initializes the contract with a trusted signer and USDC token address
    /// @param _trustedSigner Address that will sign battle outcomes
    /// @param _usdc Address of the USDC token contract
    constructor(address _trustedSigner, address _usdc) {
        trustedSigner = _trustedSigner;
        usdc = IERC20(_usdc);
    }

    /// @notice Creates a new battle proposal
    /// @param opponentAddresses Addresses of the player being challenged
    /// @param amount Amount of USDC to wager (ignored if sending ETH)
    /// @dev If sending ETH, use msg.value; if USDC, specify amount parameter
    function battleProposal(address[] memory opponentAddresses, uint amount) external payable {
        bool isNative = msg.value > 0 ? true : false;
    
        for (uint i; i < opponentAddresses.length; i++){
            require(opponentAddresses[i] != msg.sender, "Can't challenge yourself");
        }

        if (!isNative) {
            usdc.transferFrom(msg.sender, address(this), amount);
        } else {
           amount = msg.value;
        }

        Battle memory battle = Battle({
            challenger: msg.sender,
            opponentAddresses: opponentAddresses,
            amount: amount, 
            claimed: false,
            outcome: Outcome.NONE,
            isNative: isNative,
            accepted: false
        });

        s_battles[battleCounter] = battle;

        emit BattleCreated(msg.sender, opponentAddresses, battleCounter, amount, isNative);

        battleCounter++;
    }

    /// @notice Allows the opponent to accept a battle challenge
    /// @param battleId ID of the battle to accept
    /// @dev Must send matching funds (ETH or USDC) to accept
    function acceptBattle(uint battleId) public payable {
        Battle memory battle = s_battles[battleId];
        bool isValidOpponent = false;
        for (uint i = 0; i < battle.opponentAddresses.length; i++) {
            if (battle.opponentAddresses[i] == msg.sender) {
                isValidOpponent = true;
                break;
            }
        }
        require(isValidOpponent, "Not opponent");
        require(!battle.accepted, "Already accepted");
        uint amount = battle.amount;
        if (!battle.isNative) {
            usdc.transferFrom(msg.sender, address(this), amount);
        } else {
            require(msg.value == amount, "Incorrect native token amount");
        }
        
        s_battles[battleId].accepted = true;
        
        emit BattleAccepted(msg.sender, battleId);
    }
    
    /// @notice Allows the challenger to cancel an unaccepted battle
    /// @param battleId ID of the battle to cancel
    /// @dev Only the challenger can cancel, and only before the battle is accepted
    function cancelBattle(uint battleId) public {
        Battle memory battle = s_battles[battleId];
        require(msg.sender == battle.challenger, "Not challenger");
        require(!battle.accepted, "Battle already accepted");
        uint amount = battle.amount;
        
        if(battle.isNative){
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Failed to send ethers");
        } else {
            usdc.transfer(msg.sender, amount);
        }
        delete s_battles[battleId];

        emit BattleCancelled(msg.sender);
    }

    /// @notice Claims the prize for a battle winner
    /// @param battleId ID of the battle
    /// @param messageHash Hash of the battle outcome message
    /// @param signature Signature from the trusted signer
    /// @param outcome Result of the battle
    /// @dev Verifies signature and transfers funds to winner
    function claim(uint battleId, bytes32 messageHash, bytes memory signature, Outcome outcome) external {
        Battle storage battle = s_battles[battleId];
        
        require(!battle.claimed, "Battle already claimed");
        require(battle.outcome == Outcome.NONE, "Outcome already set");
        require(battle.accepted, "Battle not accepted");
        
        require(
            (outcome == Outcome.CHALLENGER && msg.sender == battle.challenger) ||
            (outcome == Outcome.OPPONENT && isOpponent(battle.opponentAddresses, msg.sender)) ||
            (outcome == Outcome.DRAW && (isOpponent(battle.opponentAddresses, msg.sender) || msg.sender == battle.challenger)),
            "Caller must be the declared winner"
        );

        require(recoverSigner(messageHash, signature) == trustedSigner, "Invalid signature");
        
        bytes32 expectedHash = keccak256(abi.encodePacked(battleId, uint(outcome)));
        require(expectedHash == messageHash, "Hash mismatch");

        battle.outcome = outcome;
        battle.claimed = true;

        uint amount = battle.amount;
        
        if (outcome == Outcome.DRAW) {
            // Handle draw by paying both parties
            if(battle.isNative){
                (bool success1, ) = battle.challenger.call{value: amount}("");
                require(success1, "Failed to send ethers to challenger");
                
                // For draws, pay the claimer if they're an opponent
                address payoutAddress = isOpponent(battle.opponentAddresses, msg.sender) ? 
                    msg.sender : battle.opponentAddresses[0];
                (bool success2, ) = payoutAddress.call{value: amount}("");
                require(success2, "Failed to send ethers to opponent");
            } else {
                usdc.transfer(battle.challenger, amount);
                address payoutAddress = isOpponent(battle.opponentAddresses, msg.sender) ? 
                    msg.sender : battle.opponentAddresses[0];
                usdc.transfer(payoutAddress, amount);
            }
        } else {
            // Handle win/loss
            amount = amount * 2;
            if(battle.isNative){
                (bool success, ) = msg.sender.call{value: amount}("");
                require(success, "Failed to send ethers");
            } else {
                usdc.transfer(msg.sender, amount);
            }
        }

        emit BattleResolved(battleId, outcome);
    }

    /// @notice Recovers the signer's address from a message hash and signature
    /// @param messageHash Hash of the original message
    /// @param signature Signature to verify
    /// @return Address of the signer
    /// @dev Uses ecrecover to verify signatures
    function recoverSigner(bytes32 messageHash, bytes memory signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        address recoveredAddress = ecrecover(messageHash, v, r, s);
        require(recoveredAddress != address(0), "Invalid signature");
        return recoveredAddress;
    }

    /// @notice Splits a signature into its r, s, v components
    /// @param sig The signature to split
    /// @return r First 32 bytes of the signature
    /// @return s Second 32 bytes of the signature
    /// @return v Recovery byte of the signature
    /// @dev Uses assembly for efficient signature splitting
    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function isOpponent(address[] memory opponents, address player) internal pure returns (bool) {
        for (uint i = 0; i < opponents.length; i++) {
            if (opponents[i] == player) {
                return true;
            }
        }
        return false;
    }


    function getBattle(uint battleId) external view returns (
        address challenger,
        address[] memory opponentAddresses,
        uint amount,
        bool claimed,
        bool isNative,
        Outcome outcome,
        bool accepted
    ) {
        Battle storage battle = s_battles[battleId];
        return (
            battle.challenger,
            battle.opponentAddresses,
            battle.amount,
            battle.claimed,
            battle.isNative,
            battle.outcome,
            battle.accepted
        );
    }
}