// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface INFT is IERC721 {
    function mint(address _to) external;

    function latestTokenId() external view returns (uint256);
}

contract Controller is Ownable, AccessControlEnumerable, Pausable {
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

contract ShopNFT is Controller {
    using SafeMath for uint256;
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public receiver;

    address public validator;

    struct Pack {
        address nft;
        address paymentToken;
        uint256 price;
        uint256 stock;
        bool isEnable;
    }

    mapping(bytes32 => Pack) public packs;

    EnumerableSet.AddressSet private discountUsed;

    event AddPack(bytes32 packId, address _nft, address paymentToken, uint256 price, uint256 stock);

    event UpdatePack(bytes32 packId, address _nft, address paymentToken, uint256 price, uint256 stock);

    event EnablePack(bytes32 packId);

    event DisablePack(bytes32 packId);

    event UpdateReceiver(address receiver);

    event BuyPack(bytes32 indexed packId, uint256 tokenId, address indexed buyer, uint256 buyAt);

    constructor() {
        receiver = msg.sender;
        validator = msg.sender;
    }

    function addPack(bytes32 _packId, address _nft, address _paymentToken, uint256 _price, uint256 _stock) external onlyManager {
        require(INFT(_nft).supportsInterface(0x80ac58cd), "Not ERC721");
        require(_stock > 0, "Must have stock");
        packs[_packId] = Pack({
            nft: _nft,
            paymentToken: _paymentToken,
            price : _price,
            stock: _stock,
            isEnable : false
        });
        emit AddPack(_packId, _nft, _paymentToken, _price, _stock);
    }

    function updatePack(bytes32 _packId, address _nft, address _paymentToken, uint256 _price, uint256 _stock) external onlyManager {
        Pack storage pack = packs[_packId];
        pack.nft = _nft;
        pack.paymentToken = _paymentToken;
        pack.price = _price;
        pack.stock = _stock;
        emit UpdatePack(_packId, _nft, _paymentToken, _price, _stock);
    }

    function disablePack(bytes32 _packId) external onlyManager {
        Pack storage pack = packs[_packId];
        pack.isEnable = false;
        emit DisablePack(_packId);
    }

    function enablePack(bytes32 _packId) external onlyManager {
        Pack storage pack = packs[_packId];
        pack.isEnable = true;
        emit EnablePack(_packId);
    }

    function getPack(bytes32 _packId) external view returns (Pack memory) {
        return packs[_packId];
    }

    function buyPack(bytes32 _packId, uint256 _quantity) public whenNotPaused {
        require(packs[_packId].isEnable, "This pack is disabled");
        for (uint256 i = 0; i < _quantity; i++) {
            _buyPack(_packId, 0);
        }
    }

    function buyPackWithDiscount(bytes32 _packId, uint256 _quantity, uint256 _discountPercent, bytes memory _sign) public whenNotPaused {
        // require(!discountUsed.contains(_msgSender()), "Discount claimed");
        require(packs[_packId].isEnable, "This pack is disabled");
        address user = _msgSender();
        bool validate = _validateDiscount(user, _packId, _discountPercent, _sign);
        require(validate, "Invalid sign");
        for (uint256 i = 0; i < _quantity; i++) {
            _buyPack(_packId, _discountPercent);
        }
    }

    function _validateDiscount(address _user, bytes32 _packId, uint256 _discountPercent, bytes memory _sign) internal view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(_user, _packId, _discountPercent));
        address signer = hash.toEthSignedMessageHash().recover(_sign);
        return signer == validator;
    }

    function _buyPack(bytes32 _packId, uint256 _discountPercent) internal {
        Pack memory pack = packs[_packId];
        if (_discountPercent > 0) {
            IERC20(pack.paymentToken).transferFrom(_msgSender(), receiver, pack.price.div(100).mul(_discountPercent));
        } else {
            IERC20(pack.paymentToken).transferFrom(_msgSender(), receiver, pack.price);
        }
        INFT(pack.nft).mint(_msgSender());
        uint256 tokenId = INFT(pack.nft).latestTokenId();
        packs[_packId].stock -= 1;
        emit BuyPack(_packId, tokenId , _msgSender(), block.timestamp);
    }

    function updateValidator(address _validator) external onlyManager {
        validator = _validator;
    }

    function updateReceiver(address _receiver) external onlyManager {
        receiver = _receiver;
        emit UpdateReceiver(_receiver);
    }
}