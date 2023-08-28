// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

abstract contract Bannable {
    mapping(address => mapping(uint256 => bool)) private _isBanned;

    modifier onlyNotBanned(address _nft, uint256 _tokenId) {
        require(!_isBanned[_nft][_tokenId], "banned");
        _;
    }

    modifier onlyBanned(address _nft, uint256 _tokenId) {
        require(_isBanned[_nft][_tokenId], "not banned");
        _;
    }

    event Ban(address nft, uint256 tokenId, string reason);

    event Unban(address nft, uint256 tokenId, string reason);

    function _ban(address _nft, uint256 _tokenId, string memory _reason) internal virtual onlyNotBanned(_nft, _tokenId) {
        _isBanned[_nft][_tokenId] = true;
        emit Ban(_nft, _tokenId, _reason);
    }

    function _unban(address _nft, uint256 _tokenId, string memory _reason) internal virtual onlyBanned(_nft, _tokenId) {
        _isBanned[_nft][_tokenId] = false;
        emit Unban(_nft, _tokenId, _reason);
    }
}

abstract contract Controller is Ownable, Pausable, Bannable {
    mapping (address => bool) managers;

    modifier onlyManager() {
        require(isManager(msg.sender), "Caller is not a manager");
        _;
    }

    function isManager(address _account) public virtual view returns (bool) {
        return managers[_account];
    }

    function addManager(address _account) public virtual onlyOwner {
        managers[_account] = true;
    }

    function removeManager(address _account) public virtual onlyOwner {
        managers[_account] = false;
    }

    function pause() public onlyManager whenNotPaused {
        _pause();
    }

    function unpause() public onlyManager whenPaused {
        _unpause();
    }
}

contract NFTMarketplace is Controller {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    IERC721 public nft;

    Counters.Counter public currentOrderId;

    uint256 public feeMarketRate;

    address public receiver;

    uint256 public minPrice;

    struct ItemSale {
        address nftAddress;
        uint256 tokenId;
        address paymentToken;
        uint256 price;
        address owner;
    }

    mapping (uint256 => ItemSale) markets;

    mapping (address => bool) _paymentTokens;

    mapping (address => bool) _listedNfts;

    event PlaceOrder(uint256 indexed orderId, address indexed nftAddress, uint256 indexed tokenId, address seller, address paymentToken, uint256 price, uint256 timestamp);

    event CancelOrder(uint256 indexed orderId, uint256 timestamp);

    event UpdatePrice(uint256 indexed orderId, uint256 newPrice, uint256 timestamp);
    
    event FillOrder(uint256 indexed orderId, address indexed nftAddress, uint256 indexed tokenId, address buyer, uint256 timestamp);

    modifier onlyListedNft(address _nftAddress) {
        require(_listedNfts[_nftAddress], "NFT not allowed");
        _;
    }

    constructor() {
        feeMarketRate = 0;
        receiver = msg.sender;
        minPrice = 0;
        newOrder(address(0), 0, address(0), 0); // The void order
    }

    function placeOrder(address _nftAddress, uint256 _tokenId, address _paymentToken, uint256 _price) external onlyListedNft(_nftAddress) {
        require(IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender(), "Not owner of NFT");
        require(_price > 0, "Nothing is free");
        if (minPrice > 0) {
            require(_price > minPrice, "Too cheap");
        }
        require(_paymentTokens[_paymentToken], "Not allowed");

        IERC721(_nftAddress).transferFrom(_msgSender(), address(this), _tokenId);

        newOrder(_nftAddress, _tokenId, _paymentToken, _price);

        uint256 orderId = currentOrderId.current() - 1;

        emit PlaceOrder(orderId, _nftAddress, _tokenId, _msgSender(), _paymentToken, _price, block.timestamp);
    }

    function cancelOrder(uint256 _orderId) external {
        ItemSale memory itemSale = markets[_orderId];
        require(itemSale.owner == _msgSender(), "not own");

        uint256 tokenId = itemSale.tokenId;
        address nftAddress = itemSale.nftAddress;

        clearOrder(_orderId, nftAddress, tokenId, _msgSender());

        emit CancelOrder(_orderId, block.timestamp);
    }

    function updatePrice(uint256 _orderId, uint256 _price) external {
        require(_price > 0, "nothing is free");
        if (minPrice > 0) {
            require(_price > minPrice, "Too cheap");
        }
        ItemSale storage itemSale = markets[_orderId];
        require(itemSale.owner == _msgSender(), "not own");

        itemSale.price = _price;

        emit UpdatePrice(_orderId, _price, block.timestamp);
    }

    function fillOrder(uint256 _orderId) external {
        ItemSale memory itemSale = markets[_orderId];
        require(itemSale.price > 0, "incorrect order");
        uint256 feeMarket = itemSale.price.mul(feeMarketRate).div(100);
        address paymentToken = itemSale.paymentToken;
        IERC20(paymentToken).transferFrom(_msgSender(), receiver, feeMarket);
        IERC20(paymentToken).transferFrom(_msgSender(), itemSale.owner, itemSale.price.sub(feeMarket));
        address nftAddress = itemSale.nftAddress;
        uint256 tokenId = itemSale.tokenId;
        clearOrder(_orderId, nftAddress, tokenId, _msgSender());
        emit FillOrder(_orderId, nftAddress, tokenId, _msgSender(), block.timestamp);
    }

    function newOrder(address _nftAddress, uint256 _tokenId, address _paymentToken, uint256 _price) internal onlyNotBanned(_nftAddress, _tokenId) {        
        uint256 orderId = currentOrderId.current();

        markets[orderId] = ItemSale({
            nftAddress : _nftAddress,
            tokenId : _tokenId,
            paymentToken: _paymentToken,
            price : _price,
            owner : _msgSender()
        });

        currentOrderId.increment();
    }

    function clearOrder(uint256 _orderId, address _nftAddress, uint256 _tokenId, address recipient) internal {
        IERC721(_nftAddress).transferFrom(address(this), recipient, _tokenId);
        markets[_orderId] = ItemSale({
            nftAddress : address(0),
            tokenId : 0,
            paymentToken: address(0),
            price : 0,
            owner : address(0)
        });
    }

    function getOrder(uint256 _orderId) external view returns (ItemSale memory) {
        return markets[_orderId];
    }

    function paymentTokens(address _address) external view returns (bool) {
        return _paymentTokens[_address];
    }
    
    function addPaymentToken(address _address) external onlyManager {
        _paymentTokens[_address] = true;
    }
    
    function removePaymentToken(address _address) external onlyManager {
        _paymentTokens[_address] = false;
    }

    function setFeeMarketRate(uint256 _feeMarketRate) external onlyManager {
        feeMarketRate = _feeMarketRate;
    }

    function isNftAllowed(address _nftAddress) external view returns (bool) {
        return _listedNfts[_nftAddress];
    }

    function listNft(address _nftAddress) external onlyManager {
        _listedNfts[_nftAddress] = true;
    }

    function delistNft(address _nftAddress) external onlyManager {
        _listedNfts[_nftAddress] = false;
    }

    function setMinPrice(uint256 _minPrice) external onlyManager {
        minPrice = _minPrice;
    }

    function setReceiver(address _receiver) external onlyManager {
        receiver = _receiver;
    }
}