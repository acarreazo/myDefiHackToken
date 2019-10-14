pragma solidity ^0.4.24;



contract EIP20Interface {
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() constant returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    /// total amount of tokens
    uint256 public totalSupply;

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) public view returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) public returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    /// @notice `msg.sender` approves `_spender` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of tokens to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) public returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    // solhint-disable-next-line no-simple-event-func-name
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}



contract WrappedEtherInterface is EIP20Interface {

  function deposit() public payable;

  function withdraw(uint amount) public;
}


contract MoneyMarketInterface {
  uint public collateralRatio;
  address[] public collateralMarkets;

  function borrow(address asset, uint amount) public returns (uint);

  function supply(address asset, uint amount) public returns (uint);

  function withdraw(address asset, uint requestedAmount) public returns (uint);

  function repayBorrow(address asset, uint amount) public returns (uint);

  function getSupplyBalance(address account, address asset) view public returns (uint);

  function getBorrowBalance(address account, address asset) view public returns (uint);

  function assetPrices(address asset) view public returns (uint);

  function calculateAccountValues(address account) view public returns (uint, uint, uint);
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, reverts on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (a == 0) {
      return 0;
    }

    uint256 c = a * b;
    require(c / a == b);

    return c;
  }

  /**
  * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b > 0); // Solidity only automatically asserts when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }

  /**
  * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a);
    uint256 c = a - b;

    return c;
  }

  /**
  * @dev Adds two numbers, reverts on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a);

    return c;
  }

  /**
  * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
  * reverts when dividing by zero.
  */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
    return a % b;
  }
}


contract CDP {
  using SafeMath for uint;
  uint constant expScale = 10**18;
  uint constant collateralRatioBuffer = 25 * 10 ** 16;
  address creator;
  address owner;
  WrappedEtherInterface weth;
  MoneyMarketInterface compoundMoneyMarket;
  EIP20Interface borrowedToken;

  event Log(uint x, string m);
  event Log(int x, string m);

  constructor (address _owner, address tokenAddress, address wethAddress, address moneyMarketAddress) public {
    creator = msg.sender;
    owner = _owner;
    borrowedToken = EIP20Interface(tokenAddress);
    compoundMoneyMarket = MoneyMarketInterface(moneyMarketAddress);
    weth = WrappedEtherInterface(wethAddress);

    weth.approve(moneyMarketAddress, uint(-1));
    borrowedToken.approve(compoundMoneyMarket, uint(-1));
  }

  /*
    @dev called from borrow factory, wraps eth and supplies weth, then borrows
     the token at address supplied in constructor
  */
  function fund() payable external {
    require(creator == msg.sender);

    weth.deposit.value(msg.value)();

    uint supplyStatus = compoundMoneyMarket.supply(weth, msg.value);
    require(supplyStatus == 0, "supply failed");

    /* --------- borrow the tokens ----------- */
    uint collateralRatio = compoundMoneyMarket.collateralRatio();
    (uint status , uint totalSupply, uint totalBorrow) = compoundMoneyMarket.calculateAccountValues(address(this));
    require(status == 0, "calculating account values failed");

    uint availableBorrow = findAvailableBorrow(totalSupply, totalBorrow, collateralRatio);

    uint assetPrice = compoundMoneyMarket.assetPrices(borrowedToken);
    /*
      available borrow & asset price are both scaled 10e18, so include extra
      scale in numerator dividing asset to keep it there
    */
    uint tokenAmount = availableBorrow.mul(expScale).div(assetPrice);
    uint borrowStatus = compoundMoneyMarket.borrow(borrowedToken, tokenAmount);
    require(borrowStatus == 0, "borrow failed");

    /* ---------- sweep tokens to user ------------- */
    uint borrowedTokenBalance = borrowedToken.balanceOf(address(this));
    borrowedToken.transfer(owner, borrowedTokenBalance);
  }


  /* @dev the factory contract will transfer tokens necessary to repay */
  function repay() external {
    require(creator == msg.sender);

    uint repayStatus = compoundMoneyMarket.repayBorrow(borrowedToken, uint(-1));
    require(repayStatus == 0, "repay failed");

    /* ---------- withdraw excess collateral weth ------- */
    uint collateralRatio = compoundMoneyMarket.collateralRatio();
    (uint status , uint totalSupply, uint totalBorrow) = compoundMoneyMarket.calculateAccountValues(address(this));
    require(status == 0, "calculating account values failed");

    uint amountToWithdraw;
    if (totalBorrow == 0) {
      amountToWithdraw = uint(-1);
    } else {
      amountToWithdraw = findAvailableWithdrawal(totalSupply, totalBorrow, collateralRatio);
    }

    uint withdrawStatus = compoundMoneyMarket.withdraw(weth, amountToWithdraw);
    require(withdrawStatus == 0 , "withdrawal failed");

    /* ---------- return ether to user ---------*/
    uint wethBalance = weth.balanceOf(address(this));
    weth.withdraw(wethBalance);
    owner.transfer(address(this).balance);
  }

  /* @dev returns borrow value in eth scaled to 10e18 */
  function findAvailableBorrow(uint currentSupplyValue, uint currentBorrowValue, uint collateralRatio) public pure returns (uint) {
    uint totalPossibleBorrow = currentSupplyValue.mul(expScale).div(collateralRatio.add(collateralRatioBuffer));
    if ( totalPossibleBorrow > currentBorrowValue ) {
      return totalPossibleBorrow.sub(currentBorrowValue).div(expScale);
    } else {
      return 0;
    }
  }

  /* @dev returns available withdrawal in eth scale to 10e18 */
  function findAvailableWithdrawal(uint currentSupplyValue, uint currentBorrowValue, uint collateralRatio) public pure returns (uint) {
    uint requiredCollateralValue = currentBorrowValue.mul(collateralRatio.add(collateralRatioBuffer)).div(expScale);
    if ( currentSupplyValue > requiredCollateralValue ) {
      return currentSupplyValue.sub(requiredCollateralValue).div(expScale);
    } else {
      return 0;
    }
  }

  /* @dev it is necessary to accept eth to unwrap weth */
  function () public payable {}
}
