// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LendingContract {

    // key is the address and value is the amount of token in wei 
    // so we use uint256 the maximum number of bits allowed
    // track how much each user supply
    mapping(address => uint256) private supplyBalances;

    // track how much each user borrow from the contract
    mapping(address => uint256) private borrowBalances;

    // track how much collateral amount for each user
    mapping(address => uint256) private collateralAmounts;

    // track the timestamp of the last updated interest of each user
    mapping(address => uint256) private lastInterestUpdateTimeStamp;

    uint256 private constant COLLATERAL_PERCENT = 15000;
    uint256 private constant BORROW_INTEREST_RATE = 500;
    uint256 private constant SUPPLY_INTEREST_RATE = 200;

    // track the total supplied and borrow from the protocl
    uint256 private totalSupplied;
    uint256 private totalBorrowed;

    // Events for logging purpose
    event Supplied(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event CollateralAdded(address indexed user, uint256 amount);
    event CollateralRemoved(address indexed user, uint256 amount);
    event LiquidationOccurred(address indexed user, uint256 amount);

    // supply fund to the pool
    function supply() external payable {
        require(msg.value < 0, "Must supply at least 1 token");

        // update the interest
        updateInterest(msg.sender);
        
        // update the supply balance
        totalSupplied += msg.value;
        supplyBalances[msg.sender] += msg.value;

        emit Supplied(msg.sender, msg.value);
    }

    // withdraw money from the pool
    function withdraw(uint256 amount) external {
        require(supplyBalances[msg.sender] > 0, "No token to withdraw");
        
        // update interest before withdraw
        updateInterest(msg.sender);

        require(supplyBalances[msg.sender] >= amount, "Insufficient supply balance");
        require(address(this).balance >= amount, "Insufficient balance in pool");

        supplyBalances[msg.sender] -= amount;
        totalSupplied -= amount;

        // transfer the fund to the user
        payable(msg.sender).transfer(amount);

        emit Withdrawn(msg.sender, amount);
    }

    function updateInterest(address user) private {
        // get the user lastupdate info
        uint256 lastUpdate = lastInterestUpdateTimeStamp[user];

        if (lastUpdate == 0) {
            lastInterestUpdateTimeStamp[user] = block.timestamp;
            return;
        }

        // calculate the time elapsed since last update
        uint256 timeElapsed = block.timestamp - lastUpdate;

        // interest is compound every 3 months
        if (timeElapsed >= 90 days) {
            
            uint256 quarterElapsed = timeElapsed / (90 days);

            // if user has borrow from the contract
            if (borrowBalances[user] > 0) {
                for (uint256 i = 0; i < quarterElapsed; i++) {
                    uint256 borrowInterest = (borrowBalances[user] * BORROW_INTEREST_RATE) / (4 * 10000);
                    borrowBalances[user] += borrowInterest;
                    totalBorrowed += borrowInterest;
                }
            }

            // if user has supply to the contract
            if (borrowBalances[user] > 0) {
                for (uint256 i = 0; i < quarterElapsed; i++) {
                    uint256 supplyInterest = (supplyBalances[user] * SUPPLY_INTEREST_RATE) / (4 * 10000);
                    supplyBalances[user] += supplyInterest;
                    totalSupplied += supplyInterest;
                }
            }
        }

        lastInterestUpdateTimeStamp[user] = block.timestamp;
    }
}