param (
    [string]$InputFile,
    [string]$OutputFile
)

$key = [byte[]]@(
    0x4D, 0x65, 0x74, 0x61, 0x6C, 0x6C, 0x69, 0x63,
    0x41, 0x6D, 0x65, 0x74, 0x68, 0x79, 0x73, 0x74,
    0x56, 0x46, 0x53, 0x32, 0x30, 0x32, 0x36, 0x21,
    0x45, 0x6E, 0x63, 0x72, 0x79, 0x70, 0x74, 0x24
)

$iv = [byte[]]@(
    0x1A, 0x3F, 0x9B, 0x82, 0x44, 0x71, 0x05, 0xE2,
    0x68, 0x90, 0xAC, 0xDF, 0x51, 0x73, 0x29, 0xB4
)

$aes = [System.Security.Cryptography.Aes]::Create()
$aes.KeySize = 256
$aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
$aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
$aes.Key = $key
$aes.IV = $iv

$encryptor = $aes.CreateEncryptor()
$inBytes = [System.IO.File]::ReadAllBytes($InputFile)
$outBytes = $encryptor.TransformFinalBlock($inBytes, 0, $inBytes.Length)
[System.IO.File]::WriteAllBytes($OutputFile, $outBytes)

# Test decryption roundtrip
$decryptor = $aes.CreateDecryptor()
$decBytes = $decryptor.TransformFinalBlock($outBytes, 0, $outBytes.Length)
if ($decBytes.Length -eq $inBytes.Length) {
    Write-Output "Successfully encrypted $InputFile -> $OutputFile ($($outBytes.Length) bytes, roundtrip OK)"
} else {
    Write-Error "Decryption mismatch!"
}
