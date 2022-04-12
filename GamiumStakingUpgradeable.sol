// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

contract GamiumStakingUpgradeable is OwnableUpgradeable, ReentrancyGuardUpgradeable {

    // Enums
    enum EarlyWithdrawPenalty {
        NO_PENALTY,
        BURN_REWARDS,
        REDISTRIBUTE_REWARDS
    }

    // Info of each user.
    struct StakeInfo {
        // How many tokens the user has provided.
        uint256 amount;
        // How many shares the user has.
        uint256 shares;
        // Reward debt.
        uint256 rewardDebt;
        // Time when user deposited.
        uint256 depositTime;
        // Time of locking
        uint256 lockedDays;
        // Time when user withdraw
        uint256 withdrawTime;
        // Address of user
        address addressOfUser;
    }

    // Address of ERC20 token contract.
    IERC20Upgradeable public tokenStaked;
    // Last time number that ERC20s distribution occurs.
    uint256 public lastRewardTime;
    // Accumulated ERC20s per share, times 1e18.
    uint256 public accERC20PerShare;
    // Total tokens deposited in the farm.
    uint256 public totalDeposits;
    // Total shares in the farm.
    uint256 public totalShares;
    // If contractor allows early withdraw on stakes
    bool public isEarlyWithdrawAllowed;
    // Minimal days to stake
    uint256 public minLockDays;
    // Maximal days to stake
    uint256 public maxLockDays;
    // Address of the ERC20 Token contract.
    IERC20Upgradeable public erc20;
    // The total amount of ERC20 that's paid out as reward.
    uint256 public paidOut;
    // ERC20 tokens rewarded per second.
    uint256 public rewardPerSecond;
    // Total rewards added to farm
    uint256 public totalFundedRewards;
    // Total current rewards
    uint256 public totalRewards;
    // Info of each user that stakes ERC20 tokens.
    mapping(address => StakeInfo[]) public stakeInfo;
    // The time when farming starts.
    uint256 public startTime;
    // The time when farming ends.
    uint256 public endTime;
    // Shares bonus per year.
    uint256 public shareBonusPerYear;
    // Early withdraw penalty
    EarlyWithdrawPenalty public penalty;
    // Reward fee percent
    uint256 public rewardFeePercent;
    // Fee collector address
    address payable public feeCollector;
    // Total tokens burned
    uint256 public totalTokensBurned;
    // Total fee collected in tokens
    uint256 public totalFeeCollectedTokens;
    // NumberOfUsers participating in farm
    uint256 public noOfUsers;
    // Addresses of all users that are currently participating
    address[] public participants;
    // Mapping of every users spot in array
    mapping(address => uint256) public id;
    // Mapping of generated rewards per user
    mapping(address => uint256) public rewardsClaimed;
    // ERC20 tokens reward much as staked token.
    uint256 public secondTokenRewardTimes;

    // Events
    event Deposit(
        address indexed user,
        uint256 indexed stakeId,
        uint256 indexed amount,
        uint256 shares
    );
    event Withdraw(
        address indexed user,
        uint256 indexed stakeId,
        uint256 indexed amount,
        uint256 shares
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed stakeId,
        uint256 indexed amount,
        uint256 shares
    );

    event EarlyWithdrawPenaltySet(EarlyWithdrawPenalty indexed penalty);
    event MinTimeToStakeSet(uint256 indexed minLockDays);
    event MaxTimeToStakeSet(uint256 indexed maxLockDays);
    event IsEarlyWithdrawAllowedSet(bool indexed allowed);
    event RewardFeePercentSet(uint256 indexed rewardFeePercent);
    event FeeCollectorSet(address payable indexed feeCollector);

    // Modifiers
    modifier validateStakeByStakeId(address _user, uint256 stakeId) {
        require(stakeId < stakeInfo[_user].length, "Stake does not exist");
        _;
    }

    /**
     * @notice function sets initial state of contract
     *
     * @param _erc20 - address of reward token
     * @param _rewardPerSecond - number of reward per second
     * @param _startTime - beginning of farm
     * @param _minLockDays - min staking time for stake
     * @param _maxLockDays - max staking time for stake
     * @param _tokenStaked - address of token which is staked
     * @param _sharesBonusPerYear - extra shares per staking year
     * @param _secondTokenRewardTimes - second token rewards per second only for view
     */
    function initialize(
        address _erc20,
        uint256 _rewardPerSecond,
        uint256 _startTime,
        uint256 _minLockDays,
        uint256 _maxLockDays,
        address _tokenStaked,
        uint256 _sharesBonusPerYear,
        uint256 _secondTokenRewardTimes
    )
        initializer
        public
    {
        // Upgrading ownership
        __Ownable_init();
        __ReentrancyGuard_init();

                    // Requires for correct initialization
        require(_erc20 != address(0x0), "Wrong token address.");
        require(_rewardPerSecond > 0, "Rewards per second must be > 0.");
        require(
            _startTime >= block.timestamp,
            "Start time can not be in the past."
        );

        erc20 = IERC20Upgradeable(_erc20);
        rewardPerSecond = _rewardPerSecond;
        startTime = _startTime;
        endTime = _startTime;
        minLockDays = _minLockDays;
        maxLockDays = _maxLockDays;
        shareBonusPerYear = _sharesBonusPerYear;
        secondTokenRewardTimes = _secondTokenRewardTimes;

        _setEarlyWithdrawPenalty(0);
        _addPool(IERC20Upgradeable(_tokenStaked));
    }

    // All Internal functions

    /**
     * @notice function is adding a new ERC20 token to the pool
     *
     * @param _tokenStaked - address of token staked
     */
    function _addPool(
        IERC20Upgradeable _tokenStaked
    )
        internal
    {
        require(
            address(_tokenStaked) != address(0x0),
            "Must input valid address."
        );
        require(
            address(tokenStaked) == address(0x0),
            "Pool can be set only once."
        );

        uint256 _lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;

        tokenStaked = _tokenStaked;
        lastRewardTime = _lastRewardTime;
        accERC20PerShare = 0;
        totalDeposits = 0;
    }

    /**
     * @notice function is setting early withdrawal penalty, if applicable
     *
     * @param _penalty - number of penalty
     */
    function _setEarlyWithdrawPenalty(
        uint256 _penalty
    )
        internal
    {
        penalty = EarlyWithdrawPenalty(_penalty);
        emit EarlyWithdrawPenaltySet(penalty);
    }

    /**
     * @notice function is setting early withdrawal penalty, if applicable
     *
     * @param _penalty - number of penalty
     */
    function setEarlyWithdrawPenalty(
        uint256 _penalty
    )
        external
        onlyOwner
    {
        penalty = EarlyWithdrawPenalty(_penalty);
        emit EarlyWithdrawPenaltySet(penalty);
    }

    /**
    * @notice function is adding participant from farm
    *
    * @param user - address of user
    *
    * @return boolean - if adding is successful or not
    */
    function _addParticipant(
        address user
    )
        internal
        returns(bool)
    {
        uint256 totalAmount = 0;
        for(uint256 i = 0; i < stakeInfo[user].length; i++){
            totalAmount += stakeInfo[user][i].amount;
        }

        if(totalAmount > 0){
            return false;
        }

        id[user] = noOfUsers;
        noOfUsers++;
        participants.push(user);

        return true;
    }

    /**
     * @notice function is removing participant from farm
     *
     * @param user - address of user
     * @param amount - how many is user withdrawing
     *
     * @return boolean - if removal is successful or not
     */
    function _removeParticipant(
        address user,
        uint256 amount
    )
        internal
        returns(bool)
    {
        uint256 totalAmount;

        if(noOfUsers == 1){
            totalAmount = 0;
            for(uint256 i = 0; i < stakeInfo[user].length; i++){
                totalAmount += stakeInfo[user][i].amount;
            }

            if(amount == totalAmount){
                delete id[user];
                participants.pop();
                noOfUsers--;

                return true;
            }
        }
        else{
            totalAmount = 0;
            for(uint256 i = 0; i < stakeInfo[user].length; i++){
                totalAmount += stakeInfo[user][i].amount;
            }

            if(amount == totalAmount){
                uint256 deletedUserId = id[user];
                address lastUserInParticipantsArray = participants[participants.length - 1];
                participants[deletedUserId] = lastUserInParticipantsArray;
                id[lastUserInParticipantsArray] = deletedUserId;

                delete id[user];
                participants.pop();
                noOfUsers--;

                return true;
            }
        }

        return false;
    }

    // All setter's functions

    /**
    * @notice function is setting second Token Reward Times
    *
    * @param _secondTokenRewardTimes - rewards time
    */
    function setSecondTokenRewardTimes(
        uint256 _secondTokenRewardTimes
    )
        external
        onlyOwner
    {
        secondTokenRewardTimes = _secondTokenRewardTimes;
    }

    /**
     * @notice function is setting new minimum time to stake value
     *
     * @param _minLockDays - min time to stake
     */
    function setMinTimeToStake(
        uint256 _minLockDays
    )
        external
        onlyOwner
    {
        minLockDays = _minLockDays;
        emit MinTimeToStakeSet(minLockDays);
    }

    /**
     * @notice function is setting new minimum time to stake value
     *
     * @param _maxLockDays - min time to stake
     */
    function setMaxTimeToStake(
        uint256 _maxLockDays
    )
        external
        onlyOwner
    {
        maxLockDays = _maxLockDays;
        emit MaxTimeToStakeSet(_maxLockDays);
    }

    /**
     * @notice function is setting new state of early withdraw
     *
     * @param _isEarlyWithdrawAllowed - is early withdraw allowed or not
     */
    function setIsEarlyWithdrawAllowed(
        bool _isEarlyWithdrawAllowed
    )
        external
        onlyOwner
    {
        isEarlyWithdrawAllowed = _isEarlyWithdrawAllowed;
        emit IsEarlyWithdrawAllowedSet(isEarlyWithdrawAllowed);
    }

    /**
     * @notice function is setting new reward fee percent value
     *
     * @param _rewardFeePercent - reward fee percent
     */
    function setRewardFeePercent(
        uint256 _rewardFeePercent
    )
        external
        onlyOwner
    {
        rewardFeePercent = _rewardFeePercent;
        emit RewardFeePercentSet(rewardFeePercent);

    }

    /**
     * @notice function is setting feeCollector on new address
     *
     * @param _feeCollector - address of newFeeCollector
     */
    function setFeeCollector(
        address payable _feeCollector
    )
        external
        onlyOwner
    {
        feeCollector = _feeCollector;
        emit FeeCollectorSet(feeCollector);
    }

    // All view functions

    /**
     * @notice function is getting number to see deposited ERC20 token for a user.
     *
     * @param _user - address of user
     * @param stakeId - id of user stake
     *
     * @return deposited ERC20 token for a user
     */
    function deposited(
        address _user,
        uint256 stakeId
    )
        public
        view
        validateStakeByStakeId(_user, stakeId)
        returns (uint256)
    {
        StakeInfo memory  stake = stakeInfo[_user][stakeId];
        return stake.amount;
    }

    /**
     * @notice function is getting number to see pending ERC20s for a user.
     *
     * @dev pending reward =
     * (user.shares * pool.accERC20PerShare) - user.rewardDebt
     *
     * @param _user - address of user
     * @param stakeId - id of user stake
     *
     * @return pending ERC20s for a user.
     */
    function pending(
        address _user,
        uint256 stakeId
    )
        public
        view
        validateStakeByStakeId(_user, stakeId)
        returns (uint256)
    {
        StakeInfo memory stake = stakeInfo[_user][stakeId];

        if (stake.shares == 0) {
            return 0;
        }

        uint256 _accERC20PerShare = accERC20PerShare;
        uint256 tokenShares = totalShares;

        if (block.timestamp > lastRewardTime && tokenShares != 0) {
            uint256 lastTime = block.timestamp < endTime
                ? block.timestamp
                : endTime;
            uint256 timeToCompare = lastRewardTime < endTime
                ? lastRewardTime
                : endTime;
            uint256 nrOfSeconds = lastTime - timeToCompare;
            uint256 erc20Reward = nrOfSeconds * rewardPerSecond;
            _accERC20PerShare = _accERC20PerShare + erc20Reward * 1e18 / tokenShares;
        }

        return
            stake.shares * _accERC20PerShare / 1e18 - stake.rewardDebt;
    }

    /**
     * @notice function is getting number to see pending ERC20s for a user.
     *
     * @dev pending reward =
     * (user.shares * pool.accERC20PerShare) - user.rewardDebt
     *
     * @param _user - address of user
     * @param stakeId - id of user stake
     *
     * @return pendingSecondToken ERC20s for a user.
     */
    function pendingSecondToken(
        address _user,
        uint256 stakeId
    )
        public
        view
        validateStakeByStakeId(_user, stakeId)
        returns (uint256)
    {
        return secondTokenRewardTimes * pending(_user,stakeId);
    }

    /**
     * @notice function is getting number to see deposit timestamp for a user.
     *
     * @param _user - address of user
     * @param stakeId - id of user stake
     *
     * @return time when user deposited specific stake
     */
    function depositTimestamp(
        address _user,
        uint256 stakeId
    )
        public
        view
        validateStakeByStakeId(_user, stakeId)
        returns (uint256)
    {
        StakeInfo memory stake = stakeInfo[_user][stakeId];
        return stake.depositTime;
    }

    /**
     * @notice function is getting number to see withdraw timestamp for a user.
     *
     * @param _user - address of user
     * @param stakeId - id of user stake
     *
     * @return time when user withdraw specific stake
     */
    function withdrawTimestamp(
        address _user,
        uint256 stakeId
    )
        public
        view
        validateStakeByStakeId(_user, stakeId)
        returns (uint256)
    {
        StakeInfo memory stake = stakeInfo[_user][stakeId];
        return stake.withdrawTime;
    }

    /**
     * @notice function is getting number to see withdraw timestamp for a user.
     *
     * @param _user - address of user
     * @param stakeId - id of user stake
     *
     * @return time is user able to withdraw
     */
    function stakeWithdrawable(
        address _user,
        uint256 stakeId
    )
        public
        view
        validateStakeByStakeId(_user, stakeId)
        returns (bool)
    {
        StakeInfo memory stake = stakeInfo[_user][stakeId];

        if (stake.depositTime + stake.lockedDays * 3600 * 24 < block.timestamp ||  isEarlyWithdrawAllowed) {
            return true;
        }
        return false;
    }

    /**
     * @notice function is getting number to see withdraw timestamp for a user.
     *
     * @param _user - address of user
     * @param stakeId - id of user stake
     *
     * @return time how many seconds for user to be able to withdraw
     */
    function stakeTimeWithdrawable(
        address _user,
        uint256 stakeId
    )
        public
        view
        validateStakeByStakeId(_user, stakeId)
        returns (uint256)
    {
        StakeInfo memory stake = stakeInfo[_user][stakeId];

        if (stake.depositTime + stake.lockedDays * 3600 * 24 < block.timestamp ||  isEarlyWithdrawAllowed) {
            return 0;
        }
        return stake.depositTime + stake.lockedDays * 3600 * 24 - block.timestamp;
    }

    /**
     * @notice function is getting user pending amounts, stakes and deposit time
     *
     * @param user - address of user
     *
     * @return array of deposits,pendingAmounts and depositTime
     */
    function getUserStakesAndPendingAmounts(
        address user
    )
        external
        view
        returns (
            uint256[] memory,
            uint256[] memory,
            uint256[] memory,
            uint256[] memory,
            bool[] memory,
            uint256[] memory
        )
    {
        uint256 numberOfStakes = stakeInfo[user].length;

        uint256[] memory deposits = new uint256[](numberOfStakes);
        uint256[] memory pendingAmounts = new uint256[](numberOfStakes);
        uint256[] memory depositTime = new uint256[](numberOfStakes);
        uint256[] memory stakeWithdrawableTime = new uint256[](numberOfStakes);
        bool[] memory stakeIsWithdrawable = new bool[](numberOfStakes);
        uint256[] memory generatedMST = new uint256[](numberOfStakes);

        for(uint256 i = 0; i < numberOfStakes; i++){
            deposits[i] = deposited(user, i);
            pendingAmounts[i] = pending(user, i);
            depositTime[i] = depositTimestamp(user, i);
            stakeWithdrawableTime[i] = stakeTimeWithdrawable(user, i);
            stakeIsWithdrawable[i] = stakeWithdrawable(user, i);
            generatedMST[i] = pendingSecondToken(user, i);
        }

        return (deposits, pendingAmounts, depositTime, stakeWithdrawableTime, stakeIsWithdrawable, generatedMST);
    }

    function totalStakeTokenGenerated(
        address user
    )
        external
        view
        returns (
            uint256
        )
    {
        uint256 _totalGMMGenerated;
        uint256 numberOfStakes = stakeInfo[user].length;

        for(uint256 i = 0; i < numberOfStakes; i++){
            _totalGMMGenerated += pending(user, i);
        }

        _totalGMMGenerated += rewardsClaimed[user];
        return _totalGMMGenerated;
    }

    function totalStakeTokenDeposited(
        address user
    )
        external
        view
        returns (
            uint256
        )
    {
        uint256 _totalstakeTokenDeposited;
        uint256 numberOfStakes = stakeInfo[user].length;

        for(uint256 i = 0; i < numberOfStakes; i++){
            _totalstakeTokenDeposited += deposited(user, i);
        }

        return _totalstakeTokenDeposited;
    }

    function totalMSTGenerated(
        address user
    )
        external
        view
        returns (
            uint256
        )
    {
        uint256 _totalMSTGenerated;
        uint256 numberOfStakes = stakeInfo[user].length;

        for(uint256 i = 0; i < numberOfStakes; i++){
            _totalMSTGenerated += pendingSecondToken(user, i);
        }

        _totalMSTGenerated += rewardsClaimed[user] * secondTokenRewardTimes;
        return _totalMSTGenerated;
    }

    function totalLANDTicketsGenerated(
        address user
    )
        external
        view
        returns (
            uint256
        )
    {
        uint256 _totalLANDGenerated;
        uint256 numberOfStakes = stakeInfo[user].length;

        for(uint256 i = 0; i < numberOfStakes; i++){
            _totalLANDGenerated += pendingSecondToken(user, i);
        }

        _totalLANDGenerated += rewardsClaimed[user];
        _totalLANDGenerated = _totalLANDGenerated / 10000;
        return _totalLANDGenerated;
    }

    // Money managing functions

    /**
     * @notice function is funding the farm, increase the end time
     *
     * @param _amount - how many tokens is funded
     */
    function fund(
        uint256 _amount
    )
        external
    {
        uint256 balanceBefore = erc20.balanceOf(address(this));
        erc20.transferFrom(address(msg.sender), address(this), _amount);
        uint256 balanceAfter = erc20.balanceOf(address(this));

        uint256 fundAmount;
        if(balanceAfter - balanceBefore <= _amount){
            fundAmount = balanceAfter - balanceBefore;
        }
        else{
            fundAmount = _amount;
        }

        totalFundedRewards = totalFundedRewards + fundAmount;
        _fundInternal(fundAmount);
    }

    /**
     * @notice function is internally funding the farm,
     * by adding farmed rewards by user to the end
     *
     * @param _amount - how many tokens is funded
     */
    function _fundInternal(
        uint256 _amount
    )
        internal
    {
        require(
            block.timestamp < endTime,
            "fund: too late, the farm is closed"
        );
        require(_amount > 0, "Amount must be greater than 0.");
        // Compute new end time
        endTime += _amount / rewardPerSecond;
        // Increase farm total rewards
        totalRewards = totalRewards + _amount;
    }

    /**
     * @notice function is updating reward,
     * variables of the given pool to be up-to-date.
     */
    function updatePool()
        public
    {
        uint256 lastTime = block.timestamp < endTime
            ? block.timestamp
            : endTime;

        if (lastTime <= lastRewardTime) {
            return;
        }

        uint256 tokenShares = totalShares;

        if (tokenShares == 0) {
            lastRewardTime = lastTime;
            return;
        }

        uint256 nrOfSeconds = lastTime - lastRewardTime;
        uint256 erc20Reward = nrOfSeconds * rewardPerSecond;

        accERC20PerShare = accERC20PerShare + (erc20Reward * 1e18/ tokenShares);
        lastRewardTime = block.timestamp;
    }

    /**
     *
     * @param amount - amount of stake
     * @param lockDays - days to lock
     *
     * @return shares number of shares.
     */
    function calculateShares(
        uint256 amount,
        uint256 lockDays
    ) public view returns (
        uint256 shares
    ) {
        uint256 longTermBonus = amount * lockDays * shareBonusPerYear / 365 / 100;
        shares = amount + longTermBonus;
    }

    /**
     *
     * @param amount - amount of stake
     * @param lockDays - days to lock
     *
     * @return amountYear number of ERC20 generated year with this APR.
     */
    function getERC20GeneratedYear(
        uint256 amount,
        uint256 lockDays
    ) public view returns (
        uint256 amountYear
    ) {
        uint256 shares = calculateShares(amount, lockDays);
        return rewardPerSecond * 3600 * 24 * 365 * shares / (totalShares + shares);
    }

    /**
     *
     * @param amount - amount of stake
     * @param lockDays - days to lock
     *
     * @return amountAPR number of ERC20 generated year with this APR.
     */
    function getERC20APR(
        uint256 amount,
        uint256 lockDays
    ) public view returns (
        uint256 amountAPR
    ) {
        uint256 amountYear = getERC20GeneratedYear(amount, lockDays);
        return amountYear * 100 / amount;
    }
    
    /**
     * @notice function is depositing ERC20 tokens to Farm for ERC20 allocation.
     *
     * @param _amount - how many tokens user is depositing
     */
    function deposit(
        uint256 _amount,
        uint256 _lockDays
    )
        external
        nonReentrant
    {
        require(
            block.timestamp < endTime,
            "Deposit: too late, the farm is closed"
        );

        // require that lockdays is between minLockDays and maxLockDays
        require(_lockDays >= minLockDays && _lockDays <= maxLockDays);

        StakeInfo memory stake;
        uint256 stakedAmount;

        updatePool();

        uint256 beforeBalance = tokenStaked.balanceOf(address(this));
        tokenStaked.transferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        
        uint256 afterBalance = tokenStaked.balanceOf(address(this));

        if(afterBalance - beforeBalance <= _amount){
            stakedAmount = afterBalance - beforeBalance;
        }
        else{
            stakedAmount = _amount;
        }

        uint256 depositShares;
        // calculate deposit shares
        depositShares = calculateShares(stakedAmount, _lockDays);

        // Increase total shares
        totalShares = totalShares + depositShares;

        // Increase total deposits
        totalDeposits = totalDeposits + stakedAmount;

        // Update user accounting
        stake.amount = stakedAmount;
        stake.shares = depositShares;
        stake.rewardDebt = stake.shares * accERC20PerShare/ 1e18;
        stake.depositTime = block.timestamp;
        // Added locked days
        stake.lockedDays = _lockDays;
        stake.addressOfUser = address(msg.sender);
        stake.withdrawTime = 0;

        _addParticipant(address(msg.sender));

        // Compute stake id
        uint256 stakeId = stakeInfo[msg.sender].length;
        // Push new stake to array of stakes for user
        stakeInfo[msg.sender].push(stake);
        // Emit deposit event
        emit Deposit(msg.sender, stakeId, stakedAmount, depositShares);
    }

    // All withdraw functions

    /**
     * @notice function is withdrawing with caring about rewards
     *
     * @param stakeId - Id of user stake
     */
    function withdraw(
        uint256 stakeId
    )
        external
        nonReentrant
        validateStakeByStakeId(msg.sender, stakeId)
    {
        bool minimalTimeStakeRespected;
        StakeInfo storage stake = stakeInfo[msg.sender][stakeId];

        uint256 _amount = stake.amount;
        uint256 _shares = stake.shares;

        require(
            stake.amount >= _amount,
            "withdraw: can't withdraw more than deposit"
        );

        updatePool();

        // check if locked days passed
        minimalTimeStakeRespected =
            stake.depositTime + stake.lockedDays <= block.timestamp;

        // if early withdraw is not allowed, user can't withdraw funds before
        if (!isEarlyWithdrawAllowed) {
            // Check if user has respected minimal time to stake, require it.
            require(
                minimalTimeStakeRespected,
                "User can not withdraw funds yet."
            );
        }

        // Compute pending rewards amount of user rewards, pending amount is with shares now
        uint256 pendingAmount = stake.shares * accERC20PerShare / 1e18 - stake.rewardDebt;

        // Penalties in case user didn't stake enough time
        if (pendingAmount > 0) {
            if (
                penalty == EarlyWithdrawPenalty.BURN_REWARDS &&
                !minimalTimeStakeRespected
            ) {
                // Burn to address (1)
                totalTokensBurned = totalTokensBurned + pendingAmount;
                _erc20Transfer(address(1), pendingAmount);
                // Update totalRewards
                totalRewards = totalRewards - pendingAmount;
            } else if (
                penalty == EarlyWithdrawPenalty.REDISTRIBUTE_REWARDS &&
                !minimalTimeStakeRespected
            ) {
                if (block.timestamp >= endTime) {
                    // Burn rewards because farm can not be funded anymore since it ended
                    _erc20Transfer(address(1), pendingAmount);
                    totalTokensBurned = totalTokensBurned + pendingAmount;
                    // Update totalRewards
                    totalRewards = totalRewards - pendingAmount;
                } else {
                    // Re-fund the farm
                    _fundInternal(pendingAmount);
                }
            } else {
                // In case either there's no penalty
                _erc20Transfer(msg.sender, pendingAmount);
                // Update totalRewards
                totalRewards = totalRewards - pendingAmount;
            }
        }

        // add reward claimed by user
        rewardsClaimed[msg.sender] += pendingAmount;

        // remove shares
        totalShares = totalShares - _shares;

        _removeParticipant(address(msg.sender), _amount);

        stake.withdrawTime = block.timestamp;
        stake.amount = stake.amount - _amount;
        stake.shares = stake.shares - _shares;
        stake.rewardDebt = stake.shares * accERC20PerShare / 1e18;

        tokenStaked.transfer(address(msg.sender), _amount);

        totalDeposits = totalDeposits - _amount;

        // Emit Withdraw event
        emit Withdraw(msg.sender, stakeId, _amount, _shares);
    }

    /**
     * @notice function is withdrawing without caring about rewards. EMERGENCY ONLY.
     *
     * @param stakeId - Id of user stake
     */
    function emergencyWithdraw(
        uint256 stakeId
    )
        external
        nonReentrant
        validateStakeByStakeId(msg.sender, stakeId)
    {
        StakeInfo storage stake = stakeInfo[msg.sender][stakeId];

        // if early withdraw is not allowed, user can't withdraw funds before
        if (!isEarlyWithdrawAllowed) {
            bool minimalTimeStakeRespected = stake.depositTime + stake.lockedDays <= block.timestamp;
            // Check if user has respected minimal time to stake, require it.
            require(
                minimalTimeStakeRespected,
                "User can not withdraw funds yet."
            );
        }

        uint256 _amount = stake.amount;
        uint256 _shares = stake.shares;

        tokenStaked.transfer(address(msg.sender), stake.amount);
        totalDeposits = totalDeposits - stake.amount;
        totalShares = totalShares - stake.shares;

        _removeParticipant(address(msg.sender), stake.amount);
        stake.withdrawTime = block.timestamp;

        stake.amount = 0;
        stake.shares = 0;
        stake.rewardDebt = 0;

        emit EmergencyWithdraw(msg.sender, stakeId, _amount, _shares);
    }

    /**
     * @notice function is withdrawing fee collected in ERC value
     */
    function withdrawCollectedFeesERC()
        external
        onlyOwner
    {
        erc20.transfer(feeCollector, totalFeeCollectedTokens);
        totalFeeCollectedTokens = 0;
    }

    /**
     * @notice function is withdrawing tokens if stuck
     *
     * @param _erc20 - address of token address
     * @param _amount - number of how many tokens
     * @param _beneficiary - address of user that collects tokens deposited by mistake
     */
    function withdrawTokensIfStuck(
        address _erc20,
        uint256 _amount,
        address _beneficiary
    )
        external
        onlyOwner
    {
        IERC20Upgradeable token = IERC20Upgradeable(_erc20);
        require(tokenStaked != token, "User tokens can not be pulled");
        require(
            _beneficiary != address(0x0),
            "_beneficiary can not be 0x0 address"
        );

        token.transfer(_beneficiary, _amount);
    }

    /**
     * @notice function is transferring ERC20,
     * and update the required ERC20 to payout all rewards
     *
     * @param _to - transfer on this address
     * @param _amount - number of how many tokens
     */
    function _erc20Transfer(
        address _to,
        uint256 _amount
    )
        internal
    {
        if (rewardFeePercent > 0) {
            // Collect reward fee
            uint256 feeAmount = _amount * rewardFeePercent / 100;
            uint256 rewardAmount = _amount - feeAmount;

            // Increase amount of fees collected
            totalFeeCollectedTokens = totalFeeCollectedTokens + feeAmount;

            // send reward
            erc20.transfer(_to, rewardAmount);
            paidOut += _amount;
        } else {
            erc20.transfer(_to, _amount);
            paidOut += _amount;
        }
    }
}