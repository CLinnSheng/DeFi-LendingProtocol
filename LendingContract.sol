// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@prb/math/contracts/PRBMathUD60x18.sol";

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
        require(msg.value > 0, "Must supply at least 1 token");

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

    // allow user to add collateral so that can loan from the pool 
    function addCollateral() external payable {
        require(msg.value > 0, "Cannot add 0 collateral");

        collateralAmounts[msg.sender] += msg.value;

        emit CollateralAdded(msg.sender, msg.value);
    }

    function removeCollateral(uint256 amount) external {
        require(amount > 0, "Cannot remove 0 collateral");
        require(collateralAmounts[msg.sender] >= amount, "Insufficient Collateral");

        // update interest before checking position
        updateInterest(msg.sender);

        uint256 requiredCollateral = (borrowBalances[msg.sender] * COLLATERAL_PERCENT) / 10000;
        require(collateralAmounts[msg.sender] - amount >= requiredCollateral, "Collateral removal would violate the lending protocol");

        collateralAmounts[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);

        emit CollateralRemoved(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "Cannot borrow 0 amount");

        // Update interest before modyfing the balances in the pool
        updateInterest(msg.sender);

        uint256 maxAmount_CanBorrow = (collateralAmounts[msg.sender] * 10000) / COLLATERAL_PERCENT;

        require(borrowBalances[msg.sender] + amount <= maxAmount_CanBorrow, "Borrow amount exceeds collateral ratio");
        require(address(this).balance - totalBorrowed >= amount, "Insufficient liquidity in contract");

        borrowBalances[msg.sender] += amount;
        totalBorrowed += amount;
        payable(msg.sender).transfer(amount);
        
        emit Borrowed(msg.sender, amount);
    }

    function repay() external payable {
        require(msg.value > 0, "Cannot repay 0 amount");

        // update interest before modifying the balances
        updateInterest(msg.sender);

        if (msg.value > borrowBalances[msg.sender]) {
            uint256 repayAmount = borrowBalances[msg.sender];

            // refund the excess amount
            uint256 refundAmount = msg.value - repayAmount;
            if (refundAmount > 0)
                payable(msg.sender).transfer(refundAmount);
        }

        borrowBalances[msg.sender] -= msg.value;
        totalBorrowed -= msg.value;

        emit Repaid(msg.sender, msg.value);
    }

    function canLiquidate(address borrower) internal view returns (bool) {
        if (borrowBalances[borrower] == 0) return false;

        // Calculate the collateral amount
        uint256 requiredCollateral = (borrowBalances[borrower] * COLLATERAL_PERCENT) / 10000;

        // if collateral is less than required, then can be liquidated
        // means that the protocol will close the borrower position
        return collateralAmounts[borrower] < requiredCollateral;
    }

    // liquidate an undercollateralized borrower
    function liquidate(address borrower) external {
        require(canLiquidate(borrower), "Borrower cannot be liquidated");

        updateInterest(borrower);

        uint256 borrowAmount = borrowBalances[borrower];
        uint256 collateralAmount = collateralAmounts[borrower];

        // close the borrower position
        borrowBalances[borrower] = 0;
        collateralAmounts[borrower] = 0;
        totalBorrowed -= borrowAmount;

        // transfer the collateral back to the user
        payable(borrower).transfer(collateralAmount);

        emit LiquidationOccurred(borrower, collateralAmount);
    }

    function updateInterest(address user) private {
        // get the user lastupdate info
        uint256 lastUpdate = lastInterestUpdateTimeStamp[user];

        if (lastUpdate == 0) {
            lastInterestUpdateTimeStamp[user] = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastUpdate;
        uint256 periods = timeElapsed / (90 days);

        // compound interest formula
        // FinalAmount = InitialAmount * (1 + InterestRate) ^ Number of Periods
        if (periods > 0) {
            // Update borrow balance with compounded interest
            if (borrowBalances[user] > 0) {
                uint256 borrowRatePerPeriod = (BORROW_INTEREST_RATE * 1e18) / (4 * 10000);
                uint256 borrowMultiplier = PRBMathUD60x18.exp2(
                    PRBMathUD60x18.mul(PRBMathUD60x18.ln(1e18 + borrowRatePerPeriod), periods)
                );
                uint256 newBorrowBalance = PRBMathUD60x18.mul(borrowBalances[user], borrowMultiplier);
                totalBorrowed += newBorrowBalance - borrowBalances[user];
                borrowBalances[user] = newBorrowBalance;
            }

            // Update supply balance with compounded interest
            if (supplyBalances[user] > 0) {
                uint256 supplyRatePerPeriod = (SUPPLY_INTEREST_RATE * 1e18) / (4 * 10000);
                uint256 supplyMultiplier = PRBMathUD60x18.exp2(
                    PRBMathUD60x18.mul(PRBMathUD60x18.ln(1e18 + supplyRatePerPeriod), periods)
                );
                uint256 newSupplyBalance = PRBMathUD60x18.mul(supplyBalances[user], supplyMultiplier);
                totalSupplied += newSupplyBalance - supplyBalances[user];
                supplyBalances[user] = newSupplyBalance;
            }
        }

        lastInterestUpdateTimeStamp[user] = block.timestamp;
    }

    function getAccountInfo(address user) external view returns (uint256 supplyBalance, uint256 borrowBalance, uint256 collateralAmount, uint256 borrowLimit) {
        supplyBalance = supplyBalances[user];
        borrowBalance = borrowBalances[user];
        collateralAmount = collateralAmounts[user];
        
        // Calculate max borrow limit based on collateral
        borrowLimit = (collateralAmount * 10000) / COLLATERAL_PERCENT;

        
        return (supplyBalance, borrowBalance, collateralAmount, borrowLimit);
    }

    function getProtocolStatus() external view returns 
    (uint256 _totalSupplied, uint256 _totalBorrowed, uint256 _availableLiquidity, uint256 _utilizationRate) {
        _availableLiquidity = address(this).balance - totalBorrowed;
        _utilizationRate = totalSupplied > 0? (totalBorrowed * 10000) / totalSupplied : 0;

        return (_totalSupplied, _totalBorrowed, _availableLiquidity, _utilizationRate);
    }
}