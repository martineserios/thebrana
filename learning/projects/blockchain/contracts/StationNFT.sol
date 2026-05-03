// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721URIStorage } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title StationNFT — identity for a registered SenseLedger device
/// @notice One NFT per physical station. Token ID is deterministic in the
///         device fingerprint hash so duplicate registration is impossible.
contract StationNFT is ERC721, ERC721URIStorage, AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    error DuplicateStation(uint256 tokenId);

    event StationRegistered(uint256 indexed tokenId, address indexed owner, string metadataURI);

    constructor(address admin, address registrar) ERC721("SenseLedger Station", "SENSST") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, registrar);
    }

    /// @notice Register a station by minting an NFT to `owner`.
    /// @dev The backend computes `fingerprint` off-chain, commits it on-chain.
    function registerStation(address owner, bytes32 fingerprint, string calldata metadataURI)
        external
        onlyRole(REGISTRAR_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = uint256(fingerprint);
        if (_ownerOf(tokenId) != address(0)) revert DuplicateStation(tokenId);

        _safeMint(owner, tokenId);
        _setTokenURI(tokenId, metadataURI);
        emit StationRegistered(tokenId, owner, metadataURI);
    }

    // ---- Required OZ overrides ----

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
