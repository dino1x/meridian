// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChickenBondManagerView {
    enum BondStatus {
        NonExistent,
        ActiveEgg,
        ChickenedIn,
        ChickenedOut
    }

    function getBondData(uint256 bondId)
        external
        view
        returns (
            address owner,
            uint256 musdPrincipal,
            uint256 startTime,
            uint256 endTime,
            uint256 claimedBMUSD,
            BondStatus status
        );

    function calcAccruedBMUSD(uint256 bondId) external view returns (uint256);
}

/// @title BondNFT
/// @notice Dynamic on-chain SVG ERC-721 Almanac Bond Certificate for Roost Chicken Bonds.
contract BondNFT {
    string public constant name = "Roost MUSD Almanac Bond";
    string public constant symbol = "ROOST-BOND";

    address public immutable bondManager;
    uint256 public totalSupply;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    error OnlyBondManager();
    error InvalidTokenId();
    error NotAuthorized();
    error ZeroAddress();

    modifier onlyBondManager() {
        if (msg.sender != bondManager) revert OnlyBondManager();
        _;
    }

    constructor(address _bondManager) {
        require(_bondManager != address(0), "Zero address");
        bondManager = _bondManager;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f;   // ERC721Metadata
    }

    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert InvalidTokenId();
        return owner;
    }

    function mint(address to, uint256 tokenId) external onlyBondManager {
        if (to == address(0)) revert ZeroAddress();
        _owners[tokenId] = to;
        unchecked {
            _balances[to] += 1;
            totalSupply += 1;
        }
        emit Transfer(address(0), to, tokenId);
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) revert NotAuthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        ownerOf(tokenId);
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        if (owner != from) revert NotAuthorized();
        if (
            msg.sender != owner &&
            _tokenApprovals[tokenId] != msg.sender &&
            !_operatorApprovals[owner][msg.sender]
        ) revert NotAuthorized();
        if (to == address(0)) revert ZeroAddress();

        delete _tokenApprovals[tokenId];
        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }

    /// @notice Generates a complete on-chain Base64 JSON + Engraved Guilloche SVG bond certificate
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address currentOwner = ownerOf(tokenId);
        (
            address bondOwner,
            uint256 musdPrincipal,
            uint256 startTime,
            uint256 endTime,
            uint256 claimedBMUSD,
            IChickenBondManagerView.BondStatus status
        ) = IChickenBondManagerView(bondManager).getBondData(tokenId);
        currentOwner;
        bondOwner;
        endTime;

        uint256 accruedBMUSD = status == IChickenBondManagerView.BondStatus.ActiveEgg
            ? IChickenBondManagerView(bondManager).calcAccruedBMUSD(tokenId)
            : claimedBMUSD;

        string memory statusStr = _statusLabel(status);
        string memory stampColor = _stampColor(status);
        string memory principalStr = _formatWholeToken(musdPrincipal);
        string memory accruedStr = _formatWholeToken(accruedBMUSD);
        string memory idStr = _toString(tokenId);
        string memory tsStr = _toString(startTime);

        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 400" width="600" height="400">',
            '<rect width="600" height="400" fill="#EFE6D2"/>',
            '<rect x="14" y="14" width="572" height="372" fill="none" stroke="#1C1A17" stroke-width="2.5"/>',
            '<rect x="20" y="20" width="560" height="360" fill="none" stroke="#1C1A17" stroke-width="0.8" stroke-dasharray="4 2"/>',
            '<text x="300" y="54" text-anchor="middle" font-family="Georgia,serif" font-size="13" letter-spacing="4" fill="#1C1A17">MEZO BITCOIN-BACKED MONETARY ALMANAC</text>',
            '<text x="300" y="86" text-anchor="middle" font-family="Georgia,serif" font-size="26" font-weight="bold" fill="#1C1A17">ROOST PERPETUAL CHICKEN BOND</text>',
            '<line x1="60" y1="102" x2="540" y2="102" stroke="#1C1A17" stroke-width="1"/>',
            _svgBody(idStr, principalStr, accruedStr, tsStr, statusStr, stampColor),
            '</svg>'
        );

        string memory json = string.concat(
            '{"name":"Roost Almanac Bond #',
            idStr,
            '","description":"On-chain Mezo MUSD Chicken Bond Certificate. Principal is principal-protected via Chicken Out or convertible to yield-amplified bMUSD via Chicken In.","attributes":[{"trait_type":"Status","value":"',
            statusStr,
            '"},{"trait_type":"Principal MUSD","value":"',
            principalStr,
            '"},{"trait_type":"Accrued bMUSD","value":"',
            accruedStr,
            '"}],"image":"data:image/svg+xml;base64,',
            _base64(bytes(svg)),
            '"}'
        );

        return string.concat("data:application/json;base64,", _base64(bytes(json)));
    }

    function _svgBody(
        string memory idStr,
        string memory principalStr,
        string memory accruedStr,
        string memory tsStr,
        string memory statusStr,
        string memory stampColor
    ) internal pure returns (string memory) {
        return string.concat(
            '<text x="50" y="145" font-family="monospace" font-size="13" fill="#5A5347">CERTIFICATE NO.</text>',
            '<text x="50" y="172" font-family="Georgia,serif" font-size="24" font-weight="bold" fill="#1C1A17">#00',
            idStr,
            '</text>',
            '<text x="320" y="145" font-family="monospace" font-size="13" fill="#5A5347">ISSUE EPOCH</text>',
            '<text x="320" y="172" font-family="monospace" font-size="18" fill="#1C1A17">',
            tsStr,
            '</text>',
            '<rect x="50" y="200" width="230" height="82" fill="#E4D8BE" stroke="#1C1A17" stroke-width="1"/>',
            '<text x="64" y="224" font-family="monospace" font-size="11" fill="#5A5347">BONDED PRINCIPAL</text>',
            '<text x="64" y="260" font-family="monospace" font-size="22" font-weight="bold" fill="#1C1A17">',
            principalStr,
            ' MUSD</text>',
            '<rect x="310" y="200" width="240" height="82" fill="#E4D8BE" stroke="#1C1A17" stroke-width="1"/>',
            '<text x="324" y="224" font-family="monospace" font-size="11" fill="#5A5347">ACCRUED / CLAIMED bMUSD</text>',
            '<text x="324" y="260" font-family="monospace" font-size="22" font-weight="bold" fill="#2E5A44">',
            accruedStr,
            ' bMUSD</text>',
            '<g transform="translate(380,315) rotate(-5)">',
            '<rect x="0" y="0" width="165" height="42" fill="none" stroke="',
            stampColor,
            '" stroke-width="2.5"/>',
            '<text x="82" y="27" text-anchor="middle" font-family="monospace" font-size="14" font-weight="bold" fill="',
            stampColor,
            '">',
            statusStr,
            '</text></g>',
            '<text x="50" y="345" font-family="Georgia,serif" font-style="italic" font-size="13" fill="#5A5347">Backed by Mezo sMUSD &amp; StabilityPool</text>'
        );
    }

    function _statusLabel(IChickenBondManagerView.BondStatus status) internal pure returns (string memory) {
        if (status == IChickenBondManagerView.BondStatus.ActiveEgg) return "INCUBATING EGG";
        if (status == IChickenBondManagerView.BondStatus.ChickenedIn) return "CHICKENED IN";
        if (status == IChickenBondManagerView.BondStatus.ChickenedOut) return "CHICKENED OUT";
        return "UNKNOWN";
    }

    function _stampColor(IChickenBondManagerView.BondStatus status) internal pure returns (string memory) {
        if (status == IChickenBondManagerView.BondStatus.ActiveEgg) return "#D9A21B";
        if (status == IChickenBondManagerView.BondStatus.ChickenedIn) return "#2E5A44";
        return "#B63A27";
    }

    function _formatWholeToken(uint256 wad) internal pure returns (string memory) {
        uint256 whole = wad / 1e18;
        uint256 frac = (wad % 1e18) / 1e16; // 2 decimal places
        string memory fracStr = frac < 10
            ? string.concat("0", _toString(frac))
            : _toString(frac);
        return string.concat(_toString(whole), ".", fracStr);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits = 0;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function _base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        bytes memory table = TABLE;

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            for {
                let dataPtr := data
                let endPtr := add(dataPtr, mload(data))
            } lt(dataPtr, endPtr) {

            } {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }
        return string(result);
    }
}
