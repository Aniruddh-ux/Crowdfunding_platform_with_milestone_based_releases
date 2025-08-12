// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Milestone-Based Crowdfunding Platform
 * @dev A crowdfunding contract that releases funds based on completed milestones
 */
contract Project {
    
    // Structs
    struct Campaign {
        address creator;
        string title;
        string description;
        uint256 fundingGoal;
        uint256 totalFunded;
        uint256 deadline;
        bool isActive;
        uint256 milestoneCount;
        uint256 completedMilestones;
        mapping(uint256 => Milestone) milestones;
        mapping(address => uint256) contributions;
        address[] contributors;
    }
    
    struct Milestone {
        string description;
        uint256 fundingPercentage; // Percentage of total funds to release
        bool isCompleted;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => bool) hasVoted;
        bool fundsReleased;
    }
    
    // State variables
    mapping(uint256 => Campaign) public campaigns;
    uint256 public campaignCounter;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant MIN_VOTE_PERCENTAGE = 51; // 51% majority required
    
    // Events
    event CampaignCreated(uint256 indexed campaignId, address indexed creator, string title);
    event ContributionMade(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event MilestoneCompleted(uint256 indexed campaignId, uint256 indexed milestoneId);
    event FundsReleased(uint256 indexed campaignId, uint256 indexed milestoneId, uint256 amount);
    event RefundIssued(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    
    // Modifiers
    modifier onlyCreator(uint256 _campaignId) {
        require(campaigns[_campaignId].creator == msg.sender, "Only campaign creator can call this");
        _;
    }
    
    modifier campaignExists(uint256 _campaignId) {
        require(_campaignId < campaignCounter, "Campaign does not exist");
        _;
    }
    
    modifier campaignActive(uint256 _campaignId) {
        require(campaigns[_campaignId].isActive, "Campaign is not active");
        require(block.timestamp < campaigns[_campaignId].deadline, "Campaign deadline has passed");
        _;
    }
    
    /**
     * @dev Core Function 1: Create a new crowdfunding campaign with milestones
     * @param _title Campaign title
     * @param _description Campaign description
     * @param _fundingGoal Target funding amount in wei
     * @param _durationInDays Campaign duration in days
     * @param _milestoneDescriptions Array of milestone descriptions
     * @param _milestonePercentages Array of funding percentages for each milestone
     */
    function createCampaign(
        string memory _title,
        string memory _description,
        uint256 _fundingGoal,
        uint256 _durationInDays,
        string[] memory _milestoneDescriptions,
        uint256[] memory _milestonePercentages
    ) external {
        require(_fundingGoal > 0, "Funding goal must be greater than 0");
        require(_durationInDays > 0, "Duration must be greater than 0");
        require(_milestoneDescriptions.length == _milestonePercentages.length, "Milestone arrays length mismatch");
        require(_milestoneDescriptions.length > 0, "At least one milestone required");
        
        // Validate that milestone percentages add up to 100%
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _milestonePercentages.length; i++) {
            totalPercentage += _milestonePercentages[i];
        }
        require(totalPercentage == 100, "Milestone percentages must add up to 100%");
        
        uint256 campaignId = campaignCounter++;
        Campaign storage newCampaign = campaigns[campaignId];
        
        newCampaign.creator = msg.sender;
        newCampaign.title = _title;
        newCampaign.description = _description;
        newCampaign.fundingGoal = _fundingGoal;
        newCampaign.deadline = block.timestamp + (_durationInDays * 1 days);
        newCampaign.isActive = true;
        newCampaign.milestoneCount = _milestoneDescriptions.length;
        
        // Create milestones
        for (uint256 i = 0; i < _milestoneDescriptions.length; i++) {
            Milestone storage milestone = newCampaign.milestones[i];
            milestone.description = _milestoneDescriptions[i];
            milestone.fundingPercentage = _milestonePercentages[i];
        }
        
        emit CampaignCreated(campaignId, msg.sender, _title);
    }
    
    /**
     * @dev Core Function 2: Contribute funds to a campaign
     * @param _campaignId The ID of the campaign to contribute to
     */
    function contributeToCampaign(uint256 _campaignId) 
        external 
        payable 
        campaignExists(_campaignId) 
        campaignActive(_campaignId) 
    {
        require(msg.value > 0, "Contribution must be greater than 0");
        
        Campaign storage campaign = campaigns[_campaignId];
        
        // Add to contributor list if first contribution
        if (campaign.contributions[msg.sender] == 0) {
            campaign.contributors.push(msg.sender);
        }
        
        campaign.contributions[msg.sender] += msg.value;
        campaign.totalFunded += msg.value;
        
        emit ContributionMade(_campaignId, msg.sender, msg.value);
    }
    
    /**
     * @dev Core Function 3: Complete milestone and release funds
     * @param _campaignId The ID of the campaign
     * @param _milestoneId The ID of the milestone to complete
     */
    function completeMilestoneAndReleaseFunds(uint256 _campaignId, uint256 _milestoneId) 
        external 
        campaignExists(_campaignId) 
        onlyCreator(_campaignId) 
    {
        Campaign storage campaign = campaigns[_campaignId];
        require(_milestoneId < campaign.milestoneCount, "Invalid milestone ID");
        require(_milestoneId == campaign.completedMilestones, "Milestones must be completed in order");
        
        Milestone storage milestone = campaign.milestones[_milestoneId];
        require(!milestone.isCompleted, "Milestone already completed");
        require(campaign.totalFunded >= campaign.fundingGoal, "Funding goal not reached");
        
        // Mark milestone as completed
        milestone.isCompleted = true;
        campaign.completedMilestones++;
        
        // Calculate and release funds
        uint256 releaseAmount = (campaign.totalFunded * milestone.fundingPercentage) / 100;
        require(!milestone.fundsReleased, "Funds already released for this milestone");
        
        milestone.fundsReleased = true;
        
        // Transfer funds to creator
        (bool success, ) = campaign.creator.call{value: releaseAmount}("");
        require(success, "Fund transfer failed");
        
        emit MilestoneCompleted(_campaignId, _milestoneId);
        emit FundsReleased(_campaignId, _milestoneId, releaseAmount);
    }
    
    // Additional helper functions
    
    /**
     * @dev Get campaign details
     */
    function getCampaignDetails(uint256 _campaignId) 
        external 
        view 
        campaignExists(_campaignId) 
        returns (
            address creator,
            string memory title,
            string memory description,
            uint256 fundingGoal,
            uint256 totalFunded,
            uint256 deadline,
            bool isActive,
            uint256 milestoneCount,
            uint256 completedMilestones
        ) 
    {
        Campaign storage campaign = campaigns[_campaignId];
        return (
            campaign.creator,
            campaign.title,
            campaign.description,
            campaign.fundingGoal,
            campaign.totalFunded,
            campaign.deadline,
            campaign.isActive,
            campaign.milestoneCount,
            campaign.completedMilestones
        );
    }
    
    /**
     * @dev Get milestone details
     */
    function getMilestoneDetails(uint256 _campaignId, uint256 _milestoneId)
        external
        view
        campaignExists(_campaignId)
        returns (
            string memory description,
            uint256 fundingPercentage,
            bool isCompleted,
            bool fundsReleased
        )
    {
        require(_milestoneId < campaigns[_campaignId].milestoneCount, "Invalid milestone ID");
        Milestone storage milestone = campaigns[_campaignId].milestones[_milestoneId];
        return (
            milestone.description,
            milestone.fundingPercentage,
            milestone.isCompleted,
            milestone.fundsReleased
        );
    }
    
    /**
     * @dev Get user's contribution to a campaign
     */
    function getUserContribution(uint256 _campaignId, address _user) 
        external 
        view 
        campaignExists(_campaignId) 
        returns (uint256) 
    {
        return campaigns[_campaignId].contributions[_user];
    }
    
    /**
     * @dev Request refund if campaign failed to reach goal
     */
    function requestRefund(uint256 _campaignId) external campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp > campaign.deadline, "Campaign still active");
        require(campaign.totalFunded < campaign.fundingGoal, "Campaign reached its goal");
        require(campaign.contributions[msg.sender] > 0, "No contribution to refund");
        
        uint256 refundAmount = campaign.contributions[msg.sender];
        campaign.contributions[msg.sender] = 0;
        campaign.totalFunded -= refundAmount;
        
        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund transfer failed");
        
        emit RefundIssued(_campaignId, msg.sender, refundAmount);
    }
}
