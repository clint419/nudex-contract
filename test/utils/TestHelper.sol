pragma solidity ^0.8.0;

library TestHelper {
    function getPaddedString(string memory input) public pure returns (bytes memory) {
        // Convert string to bytes
        bytes memory inputBytes = bytes(input);

        // Length of the string
        uint256 length = inputBytes.length;

        // Initialize the result with the length encoded as 32 bytes
        bytes memory padded = abi.encodePacked(
            bytes32(length), // Encode the length
            inputBytes // Append the string
        );

        // Pad to 32 bytes
        uint256 padding = 32 - (length % 32); // Calculate remaining padding
        if (padding != 32) {
            // Add zero-padding
            bytes memory paddingBytes = new bytes(padding);
            padded = abi.encodePacked(padded, paddingBytes);
        }

        return padded;
    }
}
