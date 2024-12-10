// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A sample Raffle contract
 * @author Wisdom Uche Ijika (mrgemini)
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2.5 contract
 */

contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    /* Types  Declarations*/
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /* State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    // @dev The duration of the lottery in seconds
    uint256 private immutable i_interval;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_keyHash;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lasTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event RaffleEnterd(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lasTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        //require(msg.value >= i_entranceFee, "Not enough ETH sent!"); < 0.8.4 solidity version
        //require(msg.value >= i_entranceFee, SendMoreToEnterRaffle());  only for 0.8.29 and above
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // 1. Make migration easier
        // 2. Makes front end "indexing" easier
        emit RaffleEnterd(msg.sender);
    }

    // When should a winner be picked ?
    /**
     * @dev This is the function that the Chainlink nodes will call to see if the lottery is ready to have a winner picked
     * The following should be true in order for upkeepNeed to be true
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has enough ETH to pay for the request
     * 4. Implicitly, your subscription has LINK
     */
    function checkUpkeep(
        bytes memory /* CheckData */
    ) public view returns (bool upkeepNeeded, bytes memory /*`performData`*/) {
        bool timeHasPassed = ((block.timestamp - s_lasTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    // Get a random number
    // Use random number to pick a player
    // Be automaticaaly called
    function performUpkeep(bytes calldata /* PerformData */) external {
        // Check to see if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep(bytes(""));
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        // Get our random number from chainlink
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactions Pattern
    function fulfillRandomWords(
        uint256, //requestId
        uint256[] calldata randomWords // Checks
    ) internal override {
        // Effects (Internal Contract State)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lasTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        // Interactions (External Contract Interaction)
        (bool won, ) = recentWinner.call{value: address(this).balance}("");
        if (!won) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lasTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
