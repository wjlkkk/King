// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract StakingRewards {
    // 质押代币（用户质押的代币）
    IERC20 public immutable stakingToken;
    // 奖励代币（用户获得的奖励代币）
    IERC20 public immutable rewardToken;

    // 合约拥有者地址
    address public immutable owner;

    // 总质押量（所有用户的质押余额总和）
    uint public totalStaked;

    // 用户质押余额映射（用户地址 => 质押余额）
    mapping(address => uint) public balances;

    // 奖励持续时间（单位：秒）
    uint public durationTime;

    // 奖励结束时间（时间戳）
    uint public endTime;

    // 上次更新时间（用于计算奖励）
    uint public lastUpdateTime;

    // 奖励速率（每秒发放的奖励代币数量）
    uint public rewardRate;

    // 每个质押代币累计的奖励（全局变量）
    uint public rewardPerTokenStored;

    // 用户上次领取奖励时的奖励系数（用户地址 => RPT）
    mapping(address => uint) public userRewardPerTokenPaid;

    // 用户待领取的奖励（用户地址 => 奖励余额）
    mapping(address => uint) public rewards;

    // 事件定义
    event Staked(address indexed user, uint amount);       // 用户质押事件
    event Withdrawn(address indexed user, uint amount);    // 用户提取事件
    event RewardPaid(address indexed user, uint reward);   // 用户领取奖励事件

    /**
     * 构造函数
     * @param _stakingToken 质押代币地址
     * @param _rewardToken 奖励代币地址
     */
    constructor(address _stakingToken, address _rewardToken) {
        require(_stakingToken != address(0), "质押代币地址无效");
        require(_rewardToken != address(0), "奖励代币地址无效");
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender; // 设置合约部署者为拥有者
    }

    /**
     * 修饰器：仅允许合约拥有者调用
     */
    modifier onlyOwner {
        require(msg.sender == owner, "不是合约拥有者");
        _;
    }

    /**
     * 修饰器：更新用户奖励状态
     * @param account 用户地址
     */
    modifier updateReward(address account) {
        // 更新全局奖励系数
        rewardPerTokenStored = rewardPerToken();
        // 更新上一次更新时间为当前时间或结束时间中的较小值
        lastUpdateTime = block.timestamp < endTime ? block.timestamp : endTime;

        // 如果账户地址有效，则更新用户的奖励信息
        if (account != address(0)) {
            rewards[account] = earned(account); // 计算并更新用户待领取的奖励
            userRewardPerTokenPaid[account] = rewardPerTokenStored; // 更新用户的奖励系数
        }
        _;
    }

    /**
     * 设置奖励持续时间
     * @param _durationTime 新的奖励持续时间（单位：秒）
     */
    function setDurationTime(uint _durationTime) external onlyOwner {
        require(block.timestamp > endTime, "当前奖励周期尚未结束");
        durationTime = _durationTime; // 更新奖励持续时间
    }

    /**
     * 设置奖励速率
     * @param _amount 新增的奖励代币数量
     */
    function setRewardRate(uint _amount) external onlyOwner {
        require(durationTime > 0, "奖励持续时间必须大于0");

        if (block.timestamp > endTime) {
            // 如果当前时间已经超过结束时间，直接设置新的奖励速率
            rewardRate = _amount / durationTime;
        } else {
            // 如果当前奖励周期未结束，剩余奖励加上新增奖励重新计算奖励速率
            uint remainingReward = rewardRate * (endTime - block.timestamp);
            rewardRate = (remainingReward + _amount) / durationTime;
        }

        // 确保奖励速率大于0
        require(rewardRate > 0, "奖励速率必须大于0");
        // 确保奖励代币余额足够支付新设置的奖励
        require(rewardRate * durationTime <= rewardToken.balanceOf(address(this)), "奖励代币余额不足");

        // 更新结束时间和上次更新时间
        endTime = block.timestamp + durationTime;
        lastUpdateTime = block.timestamp;
    }

    /**
     * 用户质押代币
     * @param amount 质押的数量
     */
    function stake(uint amount) external updateReward(msg.sender) {
        require(amount > 0, "质押数量必须大于0");
        require(block.timestamp < endTime, "质押周期已结束");

        // 将质押代币从用户地址转移到合约地址
        bool success = stakingToken.transferFrom(msg.sender, address(this), amount);
        require(success, "质押代币转移失败");

        // 更新用户的质押余额和总质押量
        balances[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount); // 触发质押事件
    }

    /**
     * 用户提取质押代币
     * @param amount 提取的数量
     */
    function withdraw(uint amount) external updateReward(msg.sender) {
        require(balances[msg.sender] >= amount, "质押余额不足");

        // 将质押代币从合约地址转移到用户地址
        bool success = stakingToken.transfer(msg.sender, amount);
        require(success, "提取代币转移失败");

        // 更新用户的质押余额和总质押量
        balances[msg.sender] -= amount;
        totalStaked -= amount;

        emit Withdrawn(msg.sender, amount); // 触发提取事件
    }

    /**
     * 计算每个质押代币累计的奖励
     * @return 每个质押代币累计的奖励
     */
    function rewardPerToken() public view returns (uint) {
        if (totalStaked == 0) {
            return rewardPerTokenStored; // 如果总质押量为0，返回当前的奖励系数
        }
        // 计算新增的奖励系数
        return rewardPerTokenStored + ((rewardRate * (block.timestamp < endTime ? block.timestamp : endTime - lastUpdateTime) * 1e18) / totalStaked);
    }

    /**
     * 计算用户可领取的奖励
     * @param account 用户地址
     * @return 用户可领取的奖励
     */
    function earned(address account) public view returns (uint) {
        // 根据用户的质押余额和奖励系数计算奖励
        return (balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    /**
     * 用户领取奖励
     */
    function getRewards() external updateReward(msg.sender) {
        uint reward = rewards[msg.sender]; // 获取用户待领取的奖励
        require(reward > 0, "没有可领取的奖励");

        rewards[msg.sender] = 0; // 清空用户的奖励余额

        // 确保合约中有足够的奖励代币
        require(rewardToken.balanceOf(address(this)) >= reward, "奖励代币余额不足");

        // 将奖励代币从合约地址转移到用户地址
        bool success = rewardToken.transfer(msg.sender, reward);
        require(success, "奖励代币转移失败");

        emit RewardPaid(msg.sender, reward); // 触发领取奖励事件
    }
}
