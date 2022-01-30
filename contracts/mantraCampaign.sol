// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract mantraCampaign is Ownable {
    // choices of a participant within a campaign
    // UNDEFINED is for internal use only and will not be available from UI
    enum CHOICE {
        WIN,
        LOSE,
        DRAW,
        UNDEFINED
    }

    // states of a campaign - OPEN, CLOSED & CALCULATING
    // a participant can enter a campaign only if a campaign state is OPEN
    enum STATE {
        OPEN,
        CLOSED,
        CALCULATING
    }

    // information collected at participant level
    struct participant {
        address sender;
        CHOICE choice;
        uint256 contributionAmount;
        uint256 winAmount;
    }

    // array of participants within a campaign
    struct participants {
        participant[] _participants;
    }

    // primary data structure to store funcding information across all campaigns and participant
    mapping(uint256 => participants) campaignParticipants;

    // a map to validate if a participant has already participated in a campaign
    mapping(uint256 => mapping(address => bool)) public mapParticipants;

    // campaigns level information
    struct campaign {
        uint256 id;
        uint256 participantCount;
        uint256 winCount;
        uint256 loseCount;
        uint256 drawCount;
        uint256 totalAmount;
        uint256 winAmount;
        uint256 loseAmount;
        uint256 drawAmount;
        STATE state;
        CHOICE result;
        bool isExisting;
    }

    // map of all campaigns
    uint256 public numCampaigns;
    mapping(uint256 => campaign) public campaigns;

    uint256 public usdEntryFee;
    uint256 public DISTRIBUTION_PERCENTAGE;
    AggregatorV3Interface internal ethUsdPriceFeed;

    constructor(address _priceFeedAddress) public {
        usdEntryFee = 50 * (10**18);
        DISTRIBUTION_PERCENTAGE = 90;
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    // validate that the minimum amount required to enter the campaign is provided
    function getEntranceFee() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 10**10; // 18 decimals
        // $50, $2,000 / ETH
        // 50/2,000
        // 50 * 100000 / 2000
        uint256 costToEnter = (usdEntryFee * 10**18) / adjustedPrice;
        return costToEnter;
    }

    // start_campaign function will be called by the admin to start a new campaign
    function start_campaign(uint256 _id) public onlyOwner {
        campaign memory newCampaign;

        require(campaigns[_id].isExisting == true, "campaign id is not unique");

        newCampaign.id = _id;
        newCampaign.state = STATE.OPEN;
        newCampaign.result = CHOICE.UNDEFINED;
        newCampaign.isExisting = true;

        newCampaign.participantCount = 0;
        newCampaign.winCount = 0;
        newCampaign.loseCount = 0;
        newCampaign.drawCount = 0;

        newCampaign.totalAmount = 0;
        newCampaign.winAmount = 0;
        newCampaign.loseAmount = 0;
        newCampaign.drawAmount = 0;

        campaigns[numCampaigns++] = newCampaign;
    }

    function enter_campaign(
        uint256 _id,
        CHOICE _choice,
        uint256 _amount
    ) public payable {
        require(
            campaigns[_id].isExisting == true,
            "invalid campaign id provided to enter campaign"
        );
        require(campaigns[_id].state == STATE.OPEN, "campaign id is not open");
        require(
            (_choice == CHOICE.WIN) ||
                (_choice == CHOICE.LOSE) ||
                (_choice == CHOICE.DRAW),
            "invalid campaign choice provided to enter campaign"
        );
        require(
            getEntranceFee() <= msg.value,
            "minimum value required to join the campaign not provided"
        );
        require(
            mapParticipants[_id][msg.sender] != true,
            "sender cannot participate more than once"
        );

        // update the funding information of the campaign
        // total number of participants, total amount collected, amount collected within the WIN, LOSE and DRAW bucket
        campaigns[_id].participantCount += 1;

        campaigns[_id].totalAmount += msg.value;
        if (_choice == CHOICE.WIN) {
            campaigns[_id].winAmount += msg.value;
            campaigns[_id].winCount += 1;
        } else if (_choice == CHOICE.LOSE) {
            campaigns[_id].loseAmount += msg.value;
            campaigns[_id].loseCount += 1;
        } else if (_choice == CHOICE.DRAW) {
            campaigns[_id].drawAmount += msg.value;
            campaigns[_id].drawCount += 1;
        }

        // add the participant to the campaignParticipants map
        participant memory newparticipant;
        newparticipant.sender = msg.sender;
        newparticipant.choice = _choice;
        newparticipant.contributionAmount = msg.value;
        campaignParticipants[_id]._participants.push(newparticipant);
    }

    function calculate_campaign_result(uint256 _id) internal {
        uint256 distributionAmount;
        uint256 distributionCount;
        // calculate the amount to be distributed based on the result of the campaign.
        // a part of the distribution amount will be reserved for infra and dev expenses.
        if (campaigns[_id].result == CHOICE.WIN) {
            distributionAmount =
                campaigns[_id].loseAmount +
                campaigns[_id].drawAmount;
            distributionCount = campaigns[_id].winCount;
        } else if (campaigns[_id].result == CHOICE.LOSE) {
            distributionAmount =
                campaigns[_id].winAmount +
                campaigns[_id].drawAmount;
            distributionCount = campaigns[_id].loseCount;
        } else if (campaigns[_id].result == CHOICE.DRAW) {
            distributionAmount =
                campaigns[_id].loseAmount +
                campaigns[_id].winAmount;
            distributionCount = campaigns[_id].drawCount;
        }

        distributionAmount =
            (distributionAmount * DISTRIBUTION_PERCENTAGE) /
            100;

        // iterate thru each of the participant within a campaign
        // say -
        //  -- number of particiants = 500 (number of participants in WIN = 250, LOSE = 200, DRAW = 50)
        //  -- total amount collected = $10,000 (amount collected in WIN = $5,000, LOSE = $4,000, DRAW = $1,000)
        //  -- result = LOSE
        //  -- amount to be distributed = 90% (of total amount collected from WIN and DRAW bucket)
        //     = 90% of $5,000 (total WIN amount) + $1,000 (total DRAW amount)  = $5,400 among 4000 participant
        //  -- if a participant contributed 'x' amount, then his/her share of profit will be x * ($5,400 / 4,000)
        //  -- this profit distribution will be funded by the amount in WIN and DRAW bucket
        for (
            uint256 index = 0;
            index < campaignParticipants[_id]._participants.length;
            index++
        ) {
            if (
                campaignParticipants[_id]._participants[index].choice ==
                campaigns[_id].result
            ) {
                campaignParticipants[_id]._participants[index].winAmount =
                    campaignParticipants[_id]
                        ._participants[index]
                        .contributionAmount *
                    (distributionAmount / distributionCount);
            } else {
                campaignParticipants[_id]._participants[index].winAmount = 0;
            }
        }
    }

    function end_campaign(uint256 _id, CHOICE _result) public onlyOwner {
        require(
            campaigns[_id].isExisting == true,
            "invalid campaign id provided for campaign closure"
        );
        require(
            (_result == CHOICE.WIN) ||
                (_result == CHOICE.LOSE) ||
                (_result == CHOICE.DRAW),
            "invalid campaign result provided for campaign closure"
        );
        campaigns[_id].state = STATE.CALCULATING;
        campaigns[_id].result = _result;
        calculate_campaign_result(_id);
        campaigns[_id].state = STATE.CLOSED;
    }

    //     function return_campaign_dashboard(uint256 _id) returns (campaign) {
    //         campaign memory newCampaign;

    //         require(campaigns[_id].isExisting != true, "campaign id not found");

    //         newCampaign.id = _id;
    //         newCampaign.state = campaigns[_id].state;
    //         newCampaign.result = campaigns[_id].result;
    //         newCampaign.isExisting = true;

    //         newCampaign.participantCount = campaigns[_id].participantCount;
    //         newCampaign.winCount = campaigns[_id].winCount;
    //         newCampaign.loseCount = campaigns[_id].loseCount;
    //         newCampaign.drawCount = campaigns[_id].drawCount;

    //         newCampaign.totalAmount = campaigns[_id].totalAmount;
    //         newCampaign.winAmount = campaigns[_id].winAmount;
    //         newCampaign.loseAmount = campaigns[_id].loseAmount;
    //         newCampaign.drawAmount = campaigns[_id].drawAmount;

    //         return newCampaign;
    //     }
}
