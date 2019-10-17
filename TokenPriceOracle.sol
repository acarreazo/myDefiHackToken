pragma solidity ^0.4.24;

import "https://github.com/smartcontractkit/chainlink/blob/develop/evm/contracts/Chainlinked.sol";

contract TokenPriceOracle is Chainlinked {
    // solium-disable-next-line zeppelin/no-arithmetic-operations
    uint256 constant private ORACLE_PAYMENT = 1 * LINK;

    bytes32 public pjobId = '76ca51361e4e444f8a9b18ae350a5725' ; //jobId for bytes32 ropsten
    bytes32 public jobId;

    event RequestFulfilled(
        bytes32 indexed requestId,
        uint256 price
    );

    mapping(bytes32 => bytes32) requests;
    mapping(bytes32 => uint256) public prices;
     
    //ropsten
    //0x20fE562d797A42Dcb3399062AE9546cd06f63280 token
    //0xc99B3D447826532722E41bc36e644ba3479E4365 oracle
    
    constructor(address _token, address _oracle) public {
        setLinkToken(_token);
        setOracle(_oracle);
        jobId = pjobId;
    }
    /*
    constructor(address _token, address _oracle, bytes32 _jobId) public {
        setLinkToken(_token);
        setOracle(_oracle);
        jobId = _jobId;
    }
    */

    /**
        @dev Request the price of ETH using Bitstamp and Coinbase, returning a median value
        @dev Value is multiplied by 100 to include 2 decimal places
    */
    function requestETHUSDPrice() public {
        Chainlink.Request memory req = newRequest(jobId, this, this.fulfill.selector);
        string[] memory api = new string[](2);
        api[0] = "https://www.bitstamp.net/api/v2/ticker/ethusd/";
        api[1] = "https://api.pro.coinbase.com/products/eth-usd/ticker";
        req.addStringArray("api", api);
        string[] memory paths = new string[](2);
        paths[0] = "$.last";
        paths[1] = "$.price";
        req.addStringArray("paths", paths);
        req.add("aggregationType", "median");
        req.add("copyPath", "aggregateValue");
        req.addInt("times", 100);
        bytes32 requestId = chainlinkRequest(req, ORACLE_PAYMENT);
        requests[requestId] = keccak256("ETHUSD");
    }


    
    function cancelRequest(
        bytes32 _requestId,
        uint256 _payment,
        bytes4 _callbackFunctionId,
        uint256 _expiration
    )
    public
    
    {
        cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
    }

    function fulfill(bytes32 _requestId, uint256 _price)
    public
    recordChainlinkFulfillment(_requestId)
    {
        emit RequestFulfilled(_requestId, _price);
        prices[requests[_requestId]] = _price;
        delete requests[_requestId];
    }

}
