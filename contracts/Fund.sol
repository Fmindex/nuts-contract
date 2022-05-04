//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SortitionSumTreeFactory.sol";
import "./DateTimeLibrary.sol";

interface IERC20 {
    function transfer(address _to, uint256 _value) external returns (bool);
    function balanceOf(address account) external returns (uint);
}

interface IEthAnchorConversionPool {
    function deposit(uint256 _amount) external;
    function redeem(uint256 _amount) external; 
}

interface IEthAnchorExchangeRateFeeder {
    function exchangeRateOf(
        address _token, 
        bool _simulate
    ) external view returns (uint256);
}

interface IERC721 {
    function balanceOf(address owner) external view returns (uint balance);

    function ownerOf(uint tokenId) external view returns (address owner);

    function safeTransferFrom(
        address from,
        address to,
        uint tokenId
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint tokenId,
        bytes calldata data
    ) external;

    function transferFrom(
        address from,
        address to,
        uint tokenId
    ) external;

    function approve(address to, uint tokenId) external;

    function getApproved(uint tokenId) external view returns (address operator);

    function setApprovalForAll(address operator, bool _approved) external;

    function isApprovedForAll(address owner, address operator)
        external
        view
        returns (bool);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

     function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract Fund {
    using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;
    SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

    using DateTimeLibrary for uint;

    // Mapping from token ID to its type
    mapping(uint => uint) private _types;

    // Mapping from token ID to its number
    mapping(uint => uint) private _numbers;

    // Mapping from token ID to its number of tickers remaining
    mapping(uint => uint) private _remainingTickets;

    // Mapping from token ID to its rarity
    mapping(uint => uint) private _rarities;

    // Mapping from user address to amount of reward they can claim
    mapping(address => uint) private _rewards;

    // Mapping of Mapping from token id to amount of its tickets used in this round
    mapping(uint => mapping(uint => uint)) private _ticketAmountUsedThisRound;

    // Mapping from wallet address to list of tokens staked by this address
    mapping(address => uint[]) private _stakedCards;

    // Mapping from round to the boolean describing this round has been drawn yet
    mapping(uint => bool) private _hasDrawn;

    // Mapping from round to the time which is valid from drawing
    mapping(uint => uint) private _timeToDraw;

    // Mapping from round to total score of that round
    mapping(uint => uint) private _totalScoreAllocated;

    // Mapping of Mapping from address to score in this round
    mapping(uint => mapping(address => uint)) private _scoreThisRound;

    uint private _originalFundForReward;
    uint private _sparedFundForReward;
    uint private _sparedFundForXXX;
    uint private _currentRoundRewardAmount;
    address private _adminWalletAddr;
    uint private _round;
    address usdtAddr = address(0xEd8C41774E71f9BF0c2C223d3a3554F496656D16);
    address aUsdtAddr = address(0xb15E56E966e2e2F4e54EbF6f5e8159Ea4f400478);
    IERC20 private _usdt = IERC20(usdtAddr);
    IERC20 private _aUsdt = IERC20(aUsdtAddr);
    IEthAnchorConversionPool private _ethAnchorConversionPool = IEthAnchorConversionPool(address(0x8BCd9F372daf4546034124077d3A6da3Fd552Cf4));
    IEthAnchorExchangeRateFeeder private _ethAnchorExchangeRateFeeder = IEthAnchorExchangeRateFeeder(address(0x79E0d9bD65196Ead00EE75aB78733B8489E8C1fA));
    IERC721 private _nft = IERC721(address(0x79E0d9bD65196Ead00EE75aB78733B8489E8C1fA)); // NFT contract
    IUniswapV2Router01 private uniswap = IUniswapV2Router01(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D)); // Uniswap

    function getReward() private {
        // Calculate price
        // TODO: check exchange rate format
        uint errorThreshold = 1;
        uint exchangeRate = _ethAnchorExchangeRateFeeder.exchangeRateOf(aUsdtAddr, true);
        uint aUsdtAmount = _aUsdt.balanceOf(address(this));
        uint currentFund = aUsdtAmount * exchangeRate;
        uint rewardAmountInUsdt = currentFund - _originalFundForReward;
        uint rewardAmountInAusdt = rewardAmountInUsdt / exchangeRate;
        uint extraReward = _sparedFundForReward * 5 / 100;
        uint totalReward = rewardAmountInAusdt + extraReward;
        
        // Get reward
        _ethAnchorConversionPool.redeem(rewardAmountInAusdt);

        // Trasnfer reward
        _currentRoundRewardAmount = totalReward;
    }

    function swapExactEthToUst(
        uint ethAmount, 
        uint minUstAmount, 
        uint deadline
    ) external {
        // Validation
        // 2022/05/30 is the last date before we start to draw
        require(block.timestamp <= DateTimeLibrary.timestampFromDateTime(2022, 5, 30, 0, 0, 0), "this function should be call before 2022/05/30");
        
        // Swap ETH to USDT
        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = usdtAddr;
        uniswap.swapExactTokensForTokens(ethAmount, minUstAmount, path, address(this), deadline);
        uint totalUsdtAmount = _usdt.balanceOf(address(this));

        // Set fund
        _originalFundForReward = totalUsdtAmount * 9 / 10;
        _sparedFundForReward = totalUsdtAmount * 8 / 100;
        _sparedFundForXXX = totalUsdtAmount * 2 / 100;
    } 

    function withdraw() external {
        // Validation
        // 2022/10/30 is the date after last draw
        require(block.timestamp >= DateTimeLibrary.timestampFromDateTime(2022, 10, 30, 0, 0, 0), "this function should be call after 2022/10/30");

        // Withdraw USDT from EthAnchor
        uint aUsdtAmount = _aUsdt.balanceOf(address(this));
        _ethAnchorConversionPool.redeem(aUsdtAmount);

        // Transfer USDT to Admin's wallet
        uint totalUsdtAmount = _usdt.balanceOf(address(this));
        _usdt.transfer(_adminWalletAddr, totalUsdtAmount);
    }

    function depositToAnchor() external {
        // Validation
        // 2022/05/30 is the last date before we start to draw
        require(block.timestamp <= DateTimeLibrary.timestampFromDateTime(2022, 5, 30, 0, 0, 0), "this function should be call before 2022/05/30");

        // Calculate USDT amount to deposit
        uint totalUsdtAmount = _usdt.balanceOf(address(this));
        uint usdtToDepositAmount = totalUsdtAmount * 4 / 5;

        // Deposit to EthAnchor
        _ethAnchorConversionPool.redeem(usdtToDepositAmount);
    }

    function stake(
        uint[][] memory tokenIds, 
        uint[][] memory ticketUseds
    ) external {
        // Validate
        require(tokenIds.length == ticketUseds.length, "length must be same");
        
        uint totalScore = 0;

        // Execute
        for (uint i = 0; i < tokenIds.length; i++) {
            uint[] memory tokenHand = tokenIds[i];
            uint[] memory ticketUsedHand = ticketUseds[i];
            require(tokenHand.length == ticketUsedHand.length, "length must be same");
            uint minTicketUsed = 0;
            uint toMultipliedScore = 0;
            uint nonMultipliedScore = 0;
            uint[] memory typesInHand = new uint[](tokenHand.length);
            uint[] memory numbersInHand = new uint[](tokenHand.length);

            for (uint j = 0; j < tokenHand.length; j++) {
                if (minTicketUsed < ticketUsedHand[j]) {
                    minTicketUsed = ticketUsedHand[j];
                }
            }

            for (uint j = 0; j < tokenHand.length; j++) {
                uint tokenId = tokenHand[j];
                uint ticketUsed = ticketUsedHand[j];

                // Validate
                require(_nft.ownerOf(tokenId) == msg.sender);
                require(_remainingTickets[tokenId] >= ticketUsed, "remaining ticket shoule be more than ticket used");

                // Move NFT token to this contract
                _nft.safeTransferFrom(msg.sender, address(this), tokenId);

                // add token to list of stakedTokens
                _stakedCards[msg.sender].push(tokenId);

                // Deduct ticket amount
                _remainingTickets[tokenId] -= ticketUsed;
                _ticketAmountUsedThisRound[_round][tokenId] = ticketUsed;

                // Calculate score for this token IDs
                toMultipliedScore += _rarities[tokenId] * minTicketUsed;
                nonMultipliedScore += _rarities[tokenId] * (ticketUsed - minTicketUsed);

                // Add type and number
                typesInHand[j] = _rarities[tokenId];
                numbersInHand[j] = _types[tokenId];
            }
            uint extraMultiplier = getExtraMultiplier(numbersInHand, typesInHand);
            totalScore += ((toMultipliedScore * extraMultiplier) + nonMultipliedScore);
        }
        
        // update total score this round
        _totalScoreAllocated[_round] += (totalScore - _scoreThisRound[_round][msg.sender]);
        _scoreThisRound[_round][msg.sender] = totalScore;

        // Set allocation of NFT user
        sortitionSumTrees.set(bytes32(_round), totalScore, bytes32(uint256(uint160(msg.sender)) << 96));
    }

    function unstake() external {
        uint[] memory stakedCards = _stakedCards[msg.sender];

        // Execute
        for (uint i = 0; i < stakedCards.length; i++) {
            uint tokenId = stakedCards[i];

            // transfer token to this msg.sender
            _nft.safeTransferFrom(address(this), msg.sender, tokenId);

            // Increase ticket amount
            uint ticketAmountUsedThisRound = _ticketAmountUsedThisRound[_round][tokenId];
            _remainingTickets[tokenId] += ticketAmountUsedThisRound;
            _ticketAmountUsedThisRound[_round][tokenId] = 0;
        }

        // Set allocation of NFT user
        sortitionSumTrees.set(bytes32(_round), 0, bytes32(uint256(uint160(msg.sender)) << 96));
    }

    function claimReward() external {
        uint reward = _rewards[msg.sender];
        _rewards[msg.sender] = 0;
        
        // transfers USDT that belong to your contract to the specified address
        _usdt.transfer(msg.sender, reward);
    }

    function setProperty(
        uint tokenId, 
        uint cardType, 
        uint cardNumber,
        uint amount, 
        uint rarity
    ) external {
        // Validation
        // Only admin can call
        require(msg.sender == _adminWalletAddr, "not admin wallet");
        // 2022/04/30 is the last date before selling period
        require(block.timestamp <= DateTimeLibrary.timestampFromDateTime(2022, 4, 30, 0, 0, 0), "this function should be call before 2022/04/30");

        // Set property of NFT
        _types[tokenId] = cardType;
        _numbers[tokenId] = cardNumber;
        _remainingTickets[tokenId] = amount;
        _rarities[tokenId] = rarity;
    }

    uint startDrawDate = DateTimeLibrary.timestampFromDateTime(2022, 4, 30, 0, 0, 0);

    function lottoDraw() external {
        // Validate
        // Can draw in that period
        require(block.timestamp >= startDrawDate + _timeToDraw[_round], "this function should be call 7 days after the latest draw");
        // Can draw only once
        require(!_hasDrawn[_round], "already drawed");
        // Set draw
        _hasDrawn[_round] = true;
        _timeToDraw[_round + 1] = _timeToDraw[_round] + (7 * DateTimeLibrary.SECONDS_PER_DAY);

        // Retrieve reward
        getReward();

        // Find winners
        uint numberOfWinners = 2;
        uint rewardEach = _currentRoundRewardAmount / numberOfWinners;
        for (uint i = 0; i < numberOfWinners; i++) {
            // Find winner
            uint drawnNumber = random(_totalScoreAllocated[_round]);
            address winner = address(uint160(uint256(sortitionSumTrees.draw(bytes32(_round), drawnNumber))));
            _rewards[winner] += rewardEach;
        }

        // Increase round
        _round++;

        sortitionSumTrees.createTree(bytes32(_round), 4);
    }

    function random(uint number) private returns(uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % number;
    }

    function getExtraMultiplier(uint[] memory numbersInHand, uint[] memory typesInHand) private returns(uint) {
        // TODO: Add sort and modify score
        // sort(numbersInHand);
        uint[] memory numbers = new uint[](13);
        uint[] memory types = new uint[](4);
        if (types[typesInHand[0]] == 5) {
            // check loyal flush / straight flush / flush
            if ((numbersInHand[0] == 0) && 
                (numbersInHand[1] == 9) && 
                (numbersInHand[2] == 10) && 
                (numbersInHand[3] == 11) && 
                (numbersInHand[4] == 12)) {
                // Royal Flush
                return 11;
            } 
            if ((numbersInHand[1] == (numbersInHand[0] + 1)) && 
                (numbersInHand[2] == (numbersInHand[0] + 2)) && 
                (numbersInHand[3] == (numbersInHand[0] + 3)) && 
                (numbersInHand[4] == (numbersInHand[0] + 4))) {
                // Straight Flush
                return 10;
            } 
        }
        if (numbers[numbersInHand[0]] == 4 || numbers[numbersInHand[1]] == 4) {
            // Four of A Kind
            return 9;
        }
        if (numbers[numbersInHand[0]] == 3 || numbers[numbersInHand[3]] == 2) {
            // Full house
            return 8;
        }
        if (numbers[numbersInHand[2]] == 3 || numbers[numbersInHand[0]] == 2) {
            // Full house
            return 7;
        }
        if (types[typesInHand[0]] == 5) {
            // Flush
            return 6;
        } 
        if ((numbersInHand[0] == 0) && 
            (numbersInHand[1] == 9) && 
            (numbersInHand[2] == 10) && 
            (numbersInHand[3] == 11) && 
            (numbersInHand[4] == 12)) {
            // Hight Straight
            return 5;
        }
        if ((numbersInHand[1] == (numbersInHand[0] + 1)) && 
            (numbersInHand[2] == (numbersInHand[0] + 2)) && 
            (numbersInHand[3] == (numbersInHand[0] + 3)) && 
            (numbersInHand[4] == (numbersInHand[0] + 4))) {
            // Straight
            return 5;
        }
        if (numbers[numbersInHand[0]] == 3 || numbers[numbersInHand[1]] == 3 || numbers[numbersInHand[2]] == 3) {
            // Three of A Kind
            return 4;
        }
        if ((numbers[numbersInHand[0]] == 2 && numbers[numbersInHand[2]] == 2) || 
            (numbers[numbersInHand[0]] == 2 && numbers[numbersInHand[3]] == 2) || 
            (numbers[numbersInHand[1]] == 2 && numbers[numbersInHand[3]] == 2)) {
            // Two Pair
            return 3;
        }
        if (numbers[numbersInHand[0]] == 2 || 
            numbers[numbersInHand[2]] == 2 || 
            numbers[numbersInHand[4]] == 2) {
            // One Pair
            return 2;
        }
        return 1;
    }
}
