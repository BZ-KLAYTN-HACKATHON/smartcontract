// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

abstract contract Bannable {
    mapping(uint256 => bool) private _isBanned;

    modifier onlyNotBanned(uint256 _tokenId) {
        require(!_isBanned[_tokenId], "banned");
        _;
    }

    modifier onlyBanned(uint256 _tokenId) {
        require(_isBanned[_tokenId], "not banned");
        _;
    }

    event Ban(uint256 tokenId, string reason);

    event Unban(uint256 tokenId, string reason);

    function _ban(uint256 _tokenId, string memory _reason) internal virtual onlyNotBanned(_tokenId) {
        _isBanned[_tokenId] = true;
        emit Ban(_tokenId, _reason);
    }

    function _unban(uint256 _tokenId, string memory _reason) internal virtual onlyBanned(_tokenId) {
        _isBanned[_tokenId] = false;
        emit Unban(_tokenId, _reason);
    }
}

abstract contract RestrictTransfer {
    mapping (uint256 => bool) _isRestricted;

    mapping (address => bool) _whitelistSenders;

    mapping (address => bool) _whitelistReceivers;

    function _isWhitelistSender(address _address) public view returns (bool) {
        return _whitelistSenders[_address];
    }

    function _addWhitelistSender(address _address) internal virtual {
        require(!_isWhitelistSender(_address), "added");
        _whitelistSenders[_address] = true;
    }

    function _removeWhitelistSender(address _address) internal virtual {
        require(_isWhitelistSender(_address), "not whitelist");
        _whitelistSenders[_address] = false;
    }

    function _isWhitelistReceiver(address _address) public view returns (bool) {
        return _whitelistReceivers[_address];
    }

    function _addWhitelistReceiver(address _address) internal virtual {
        require(!_isWhitelistReceiver(_address), "added");
        _whitelistReceivers[_address] = true;
    }

    function _removeWhitelistReceiver(address _address) internal virtual {
        require(!_isWhitelistReceiver(_address), "not whitelist");
        _whitelistReceivers[_address] = false;
    }
}

contract Controller is Ownable, Pausable, Bannable, RestrictTransfer {
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

    function ban(uint256 _tokenId, string memory _reason) public onlyManager onlyNotBanned(_tokenId) {
        _ban(_tokenId, _reason);
    }

    function unban(uint256 _tokenId, string memory _reason) public onlyManager onlyBanned(_tokenId) {
        _unban(_tokenId, _reason);
    }

    function addWhitelistSender(address _address) public onlyManager {
        _addWhitelistSender(_address);
    }

    function removeWhitelistSender(address _address) public onlyManager {
        _removeWhitelistSender(_address);
    }

    function addWhitelistReceiver(address _address) public onlyManager {
        _addWhitelistReceiver(_address);
    }

    function removeWhitelistReceiver(address _address) public onlyManager {
        _removeWhitelistReceiver(_address);
    }

    function restrictTransfer(uint256 _tokenId) public onlyManager {
        _isRestricted[_tokenId] = true;
    }

    function isRestrictedTransfer(uint256 _tokenId) public view returns (bool) {
        return _isRestricted[_tokenId];
    }
}

contract NFT is ERC721, Controller {
    using SafeMath for uint256;

    struct Data {
        uint256 bornAt;
    }

    uint256 private _latestTokenId;

    mapping (uint256 => Data) public nfts;

    mapping (address => bool) _spawners;

    modifier onlySpawner {
        require(_spawners[msg.sender] || owner() == msg.sender, "require Spawner");
        _;
    }

    event MintNFT(uint256 indexed tokenId, address to);

    constructor() ERC721("IdolWorld NFT", "IDWNFT") {

    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://nft-api.bravechain.net/nft/";
    }

    function mint(address _to) public onlySpawner whenNotPaused {
        uint256 nextTokenId = _getNextTokenId();
        _mint(_to, nextTokenId);

        nfts[nextTokenId] = Data({
            bornAt: block.timestamp
        });

        emit MintNFT(nextTokenId, _to);
    }

    function _mint(address to, uint256 tokenId) internal override(ERC721) {
        super._mint(to, tokenId);

        _incrementTokenId();
    }

    function latestTokenId() external view returns (uint256) {
        return _latestTokenId;
    }

    function _getNextTokenId() private view returns (uint256) {
        return _latestTokenId.add(1);
    }

    function _incrementTokenId() private {
        _latestTokenId++;
    }

    function spawners(address _address) external view returns (bool) {
       return _spawners[_address];
    }

    function addSpawner(address _address) external onlyManager {
        _spawners[_address] = true;
    }

    function removeSpawner(address _address) external onlyManager {
        _spawners[_address] = false;
    }

    function _transfer(address from, address to, uint256 tokenId) internal virtual override {
        if (_isRestricted[tokenId]) {
            require(_whitelistSenders[from] || _whitelistReceivers[to], "not whitelist");
        }
        super._transfer(from, to, tokenId);
    }
}