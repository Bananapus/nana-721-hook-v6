// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Import the forge-std test framework.
import {Test} from "forge-std/Test.sol";
// Import IERC20 for the encodeCall used in the low-level call pattern.
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mimics USDT's void-returning transfer/transferFrom/approve behavior.
/// @dev Identical to nana-core-v6/test/mock/MockUSDT.sol, inlined here to avoid cross-repo imports.
contract MockUSDT {
    // Token metadata matching USDT's 6-decimal convention.
    string public name = "Mock Tether USD";
    // Short ticker symbol for the mock token.
    string public symbol = "USDT";
    // USDT uses 6 decimals, not 18 like most ERC-20 tokens.
    uint8 public decimals = 6;
    // Running total of all minted tokens.
    uint256 public totalSupply;

    // Maps each address to its token balance.
    mapping(address => uint256) public balanceOf;
    // Maps owner => spender => allowance for delegated transfers.
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Mints tokens to a recipient (test helper, not part of USDT interface).
    /// @param to The address to receive newly minted tokens.
    /// @param amount The number of tokens to mint.
    function mint(address to, uint256 amount) external {
        // Credit the recipient's balance with the minted amount.
        balanceOf[to] += amount;
        // Increase the total supply to reflect the new tokens.
        totalSupply += amount;
    }

    /// @notice Sets the spender's allowance. Returns VOID like real USDT.
    /// @param spender The address authorized to spend tokens.
    /// @param amount The maximum amount the spender can transfer.
    function approve(address spender, uint256 amount) external {
        // Record the new allowance for the caller-spender pair.
        allowance[msg.sender][spender] = amount;
        // Use assembly to return without any data (void), matching USDT behavior.
        assembly {
            return(0, 0)
        }
    }

    /// @notice Transfers tokens from caller to recipient. Returns VOID like real USDT.
    /// @param to The address to receive the tokens.
    /// @param amount The number of tokens to transfer.
    function transfer(address to, uint256 amount) external {
        // Ensure the sender has enough tokens to cover the transfer.
        require(balanceOf[msg.sender] >= amount, "MockUSDT: insufficient balance");
        // Debit the sender's balance by the transfer amount.
        balanceOf[msg.sender] -= amount;
        // Credit the recipient's balance with the transferred tokens.
        balanceOf[to] += amount;
        // Use assembly to return without any data (void), matching USDT behavior.
        assembly {
            return(0, 0)
        }
    }

    /// @notice Transfers tokens on behalf of an owner. Returns VOID like real USDT.
    /// @param from The address whose tokens are being spent.
    /// @param to The address to receive the tokens.
    /// @param amount The number of tokens to transfer.
    function transferFrom(address from, address to, uint256 amount) external {
        // Ensure the owner has enough tokens for the transfer.
        require(balanceOf[from] >= amount, "MockUSDT: insufficient balance");
        // Ensure the caller is authorized to spend at least this amount.
        require(allowance[from][msg.sender] >= amount, "MockUSDT: insufficient allowance");
        // Reduce the caller's remaining allowance by the transferred amount.
        allowance[from][msg.sender] -= amount;
        // Debit the owner's balance by the transfer amount.
        balanceOf[from] -= amount;
        // Credit the recipient's balance with the transferred tokens.
        balanceOf[to] += amount;
        // Use assembly to return without any data (void), matching USDT behavior.
        assembly {
            return(0, 0)
        }
    }
}

/// @notice Tests that JB721TiersHookLib's low-level call pattern (lines 605-611) handles
/// void-returning tokens like USDT correctly.
/// @dev The fix replaced `try IERC20.transfer()` with a low-level call that checks:
///   1. The call succeeded (callSuccess == true)
///   2. Either no data was returned (void) OR the returned data decodes to true
/// This test exercises that exact pattern against a void-returning mock.
contract USDTVoidReturnCompat is Test {
    // The USDT mock token instance.
    MockUSDT public usdt;
    // Address that simulates the hook contract holding tokens for distribution.
    address public hookCaller;
    // Address that receives split payout funds.
    address public splitBeneficiary;

    function setUp() public {
        // Deploy the void-returning USDT mock.
        usdt = new MockUSDT();
        // Label the USDT contract for clearer trace output.
        vm.label(address(usdt), "MockUSDT");
        // Create a caller address that simulates the hook distributing tokens.
        hookCaller = makeAddr("hookCaller");
        // Create a beneficiary address that receives split payouts.
        splitBeneficiary = makeAddr("splitBeneficiary");
    }

    // =========================================================================
    //  Test 1: The exact low-level call pattern from JB721TiersHookLib works
    //          with void-returning tokens
    // =========================================================================

    /// @notice Proves the fixed transfer pattern handles USDT's void return.
    /// @dev This replicates the exact code from JB721TiersHookLib lines 609-611:
    ///   (bool callSuccess, bytes memory returndata) =
    ///       address(token).call(abi.encodeCall(IERC20.transfer, (split.beneficiary, amount)));
    ///   if (!callSuccess || (returndata.length != 0 && !abi.decode(returndata, (bool)))) return false;
    function test_lowLevelTransfer_voidReturn_succeeds() public {
        // The amount to transfer in the split payout.
        uint256 amount = 500e6;
        // Mint USDT to the hook caller (simulating tokens held by the 721 hook).
        usdt.mint(hookCaller, amount);

        // Execute the exact low-level call pattern from JB721TiersHookLib.
        vm.prank(hookCaller);
        // Encode the transfer call exactly as the library does.
        (bool callSuccess, bytes memory returndata) =
            address(usdt).call(abi.encodeCall(IERC20.transfer, (splitBeneficiary, amount)));

        // Verify the low-level call did not revert.
        assertTrue(callSuccess, "Low-level transfer call should succeed");

        // Verify void return: USDT returns no data, so returndata.length should be 0.
        assertEq(returndata.length, 0, "Void-returning token should return empty data");

        // Verify the combined condition from line 611 evaluates correctly.
        // For void returns: callSuccess=true, returndata.length=0, so the condition is false (no revert).
        bool wouldRevert = !callSuccess || (returndata.length != 0 && !abi.decode(returndata, (bool)));
        // The pattern should NOT flag this as a failure.
        assertFalse(wouldRevert, "The fixed pattern should accept void returns as success");

        // Verify the beneficiary actually received the tokens.
        assertEq(usdt.balanceOf(splitBeneficiary), amount, "Beneficiary should receive the full transfer amount");
        // Verify the caller's balance was debited.
        assertEq(usdt.balanceOf(hookCaller), 0, "Caller should have zero balance after transfer");
    }

    // =========================================================================
    //  Test 2: The pattern also works with standard bool-returning tokens
    // =========================================================================

    /// @notice Ensures the low-level call pattern still works with compliant ERC-20 tokens.
    /// @dev A standard token returns abi.encode(true) — the pattern must accept this too.
    function test_lowLevelTransfer_boolReturn_succeeds() public {
        // Deploy a standard ERC-20 that returns bool (using forge's mock).
        StandardMockERC20 standardToken = new StandardMockERC20();
        // Label it for tracing.
        vm.label(address(standardToken), "StandardERC20");
        // The amount to transfer.
        uint256 amount = 500e6;
        // Mint tokens to the hook caller.
        standardToken.mint(hookCaller, amount);

        // Execute the exact low-level call pattern from JB721TiersHookLib.
        vm.prank(hookCaller);
        // Encode the transfer call.
        (bool callSuccess, bytes memory returndata) =
            address(standardToken).call(abi.encodeCall(IERC20.transfer, (splitBeneficiary, amount)));

        // Verify the low-level call succeeded.
        assertTrue(callSuccess, "Low-level transfer call should succeed for standard token");

        // Standard tokens return 32 bytes encoding `true`.
        assertEq(returndata.length, 32, "Standard token should return 32 bytes of data");

        // Verify the combined condition correctly accepts a true return.
        bool wouldRevert = !callSuccess || (returndata.length != 0 && !abi.decode(returndata, (bool)));
        // Should NOT flag as failure since the decoded bool is true.
        assertFalse(wouldRevert, "The pattern should accept bool(true) returns as success");

        // Verify the beneficiary received the tokens.
        assertEq(standardToken.balanceOf(splitBeneficiary), amount, "Beneficiary should receive tokens");
    }

    // =========================================================================
    //  Test 3: The pattern correctly rejects a return-false token
    // =========================================================================

    /// @notice Ensures the pattern detects when a token returns false.
    /// @dev A token that returns abi.encode(false) without reverting should be caught.
    function test_lowLevelTransfer_returnsFalse_detected() public {
        // Deploy a token that returns false on transfer.
        ReturnFalseToken falseToken = new ReturnFalseToken();
        // Label it for tracing.
        vm.label(address(falseToken), "ReturnFalseToken");
        // The amount doesn't matter since the token always returns false.
        uint256 amount = 500e6;
        // Mint tokens to the caller.
        falseToken.mint(hookCaller, amount);

        // Execute the exact low-level call pattern from JB721TiersHookLib.
        vm.prank(hookCaller);
        (bool callSuccess, bytes memory returndata) =
            address(falseToken).call(abi.encodeCall(IERC20.transfer, (splitBeneficiary, amount)));

        // The call itself succeeds (no revert), but the return value is false.
        assertTrue(callSuccess, "Low-level call should not revert");

        // Verify the combined condition catches the false return.
        bool wouldRevert = !callSuccess || (returndata.length != 0 && !abi.decode(returndata, (bool)));
        // The pattern SHOULD flag this as a failure.
        assertTrue(wouldRevert, "The pattern should detect false return and flag failure");
    }

    // =========================================================================
    //  Test 4: The pattern correctly handles a reverting token
    // =========================================================================

    /// @notice Ensures the pattern handles a reverting transfer gracefully.
    /// @dev If the transfer reverts, callSuccess is false, and the pattern returns false.
    function test_lowLevelTransfer_revert_detected() public {
        // Use MockUSDT but don't give the caller any tokens — transfer will revert.
        uint256 amount = 500e6;

        // Execute the low-level call with insufficient balance.
        vm.prank(hookCaller);
        (bool callSuccess,) = address(usdt).call(abi.encodeCall(IERC20.transfer, (splitBeneficiary, amount)));

        // The call should fail because the caller has zero balance.
        assertFalse(callSuccess, "Transfer should fail with insufficient balance");
    }
}

/// @notice A standard ERC-20 mock that returns true on transfer (compliant behavior).
contract StandardMockERC20 {
    // Token name for identification.
    string public name = "Standard Mock";
    // Token symbol.
    string public symbol = "STD";
    // Uses 6 decimals to match USDT comparison.
    uint8 public decimals = 6;
    // Running total supply.
    uint256 public totalSupply;

    // Balance mapping.
    mapping(address => uint256) public balanceOf;
    // Allowance mapping.
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Mints tokens to a recipient (test helper).
    function mint(address to, uint256 amount) external {
        // Credit the recipient.
        balanceOf[to] += amount;
        // Increase total supply.
        totalSupply += amount;
    }

    /// @notice Standard transfer that returns true.
    function transfer(address to, uint256 amount) external returns (bool) {
        // Check the sender has enough balance.
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        // Debit the sender.
        balanceOf[msg.sender] -= amount;
        // Credit the recipient.
        balanceOf[to] += amount;
        // Return true per ERC-20 spec.
        return true;
    }
}

/// @notice A mock ERC-20 that returns false on transfer without reverting.
contract ReturnFalseToken {
    // Token name for identification.
    string public name = "Return False";
    // Token symbol.
    string public symbol = "RF";
    // Uses 6 decimals.
    uint8 public decimals = 6;
    // Running total supply.
    uint256 public totalSupply;

    // Balance mapping.
    mapping(address => uint256) public balanceOf;

    /// @notice Mints tokens to a recipient (test helper).
    function mint(address to, uint256 amount) external {
        // Credit the recipient.
        balanceOf[to] += amount;
        // Increase total supply.
        totalSupply += amount;
    }

    /// @notice Always returns false without reverting (malicious/broken token behavior).
    function transfer(address, uint256) external pure returns (bool) {
        // Return false to simulate a failed transfer that doesn't revert.
        return false;
    }
}
