// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";
import {JBOwnable} from "@bananapus/ownable-v6/src/JBOwnable.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import {JB721TiersHook} from "./JB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "./interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHook} from "./interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";
import {JBDeploy721TiersHookConfig} from "./structs/JBDeploy721TiersHookConfig.sol";

/// @title JB721TiersHookDeployer
/// @notice Deploys a `JB721TiersHook` for an existing project.
contract JB721TiersHookDeployer is ERC2771Context, IJB721TiersHookDeployer {
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice A registry which stores references to contracts and their deployers.
    IJBAddressRegistry public immutable ADDRESS_REGISTRY;

    /// @notice A 721 tiers hook.
    JB721TiersHook public immutable HOOK;

    /// @notice The contract that stores and manages data for this contract's NFTs.
    IJB721TiersHookStore public immutable STORE;

    //*********************************************************************//
    // ----------------------- internal properties ----------------------- //
    //*********************************************************************//

    /// @notice This contract's current nonce, used for the Juicebox address registry.
    uint256 internal _nonce;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param hook Reference copy of a hook.
    /// @param store The contract that stores and manages data for this contract's NFTs.
    /// @param addressRegistry A registry which stores references to contracts and their deployers.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        JB721TiersHook hook,
        IJB721TiersHookStore store,
        IJBAddressRegistry addressRegistry,
        address trustedForwarder
    )
        ERC2771Context(trustedForwarder)
    {
        HOOK = hook;
        STORE = store;
        ADDRESS_REGISTRY = addressRegistry;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Deploys a 721 tiers hook for the specified project.
    /// @param projectId The ID of the project to deploy the hook for.
    /// @param deployTiersHookConfig The config to deploy the hook with, which determines its behavior.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return newHook The address of the newly deployed hook.
    function deployHookFor(
        uint256 projectId,
        JBDeploy721TiersHookConfig calldata deployTiersHookConfig,
        bytes32 salt
    )
        external
        override
        returns (IJB721TiersHook newHook)
    {
        // Deploy the governance variant specified by the config.
        newHook = IJB721TiersHook(
            salt == bytes32(0)
                ? LibClone.clone(address(HOOK))
                : LibClone.cloneDeterministic({
                    value: 0,
                    implementation: address(HOOK),
                    salt: keccak256(abi.encode(_msgSender(), salt))
                })
        );

        emit HookDeployed({projectId: projectId, hook: newHook, caller: msg.sender});

        newHook.initialize({
            projectId: projectId,
            name: deployTiersHookConfig.name,
            symbol: deployTiersHookConfig.symbol,
            baseUri: deployTiersHookConfig.baseUri,
            tokenUriResolver: deployTiersHookConfig.tokenUriResolver,
            contractUri: deployTiersHookConfig.contractUri,
            tiersConfig: deployTiersHookConfig.tiersConfig,
            flags: deployTiersHookConfig.flags
        });

        // Transfer the hook's ownership to the address that called this function.
        JBOwnable(address(newHook)).transferOwnership(_msgSender());

        // Increment the nonce.
        ++_nonce;

        // Add the hook to the address registry. This contract's nonce starts at 1.
        salt == bytes32(0)
            ? ADDRESS_REGISTRY.registerAddress({deployer: address(this), nonce: _nonce})
            : ADDRESS_REGISTRY.registerAddress({
                deployer: address(this),
                salt: keccak256(abi.encode(_msgSender(), salt)),
                bytecode: LibClone.initCode(address(HOOK))
            });
    }
}
