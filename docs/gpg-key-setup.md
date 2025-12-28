# GPG Key Setup for Omni

Omni encrypts etcd data at rest using a GPG key. This is a one-time setup that
must be done correctly—Omni will fail to start if the key is misconfigured.

## Requirements

- GPG key **must have no passphrase** (empty)
- Key must include an encryption-capable subkey
- RSA 4096-bit recommended

## Quick Setup

### 1. Generate the Primary Key

```bash
gpg --quick-generate-key "Omni (etcd encryption) <your@email.com>" rsa4096 cert never
```

- `cert` — primary key can only certify (sign other keys)
- `never` — key never expires

Note the fingerprint output (40 hex characters). You'll need it for the next step.

### 2. Add Encryption Subkey

```bash
gpg --quick-add-key <FINGERPRINT> rsa4096 encr never
```

- `encr` — subkey can encrypt data
- Replace `<FINGERPRINT>` with the full fingerprint from step 1

### 3. Export the Key

```bash
gpg --export-secret-keys --armor <FINGERPRINT> > omni.asc
```

### 4. Verify the Export

```bash
gpg --show-keys omni.asc
```

You should see:

- `sec` line (secret primary key) with `[C]` capability
- `ssb` line (secret subkey) with `[E]` capability

Example output:

```text
sec   rsa4096 2024-12-27 [C]
      ABC123...
uid           Omni (etcd encryption) <your@email.com>
ssb   rsa4096 2024-12-27 [E]
```

## Gotchas

### "No passphrase" Really Means Empty

When GPG prompts for a passphrase during generation, leave it blank and confirm.
Some GPG versions will warn you—proceed anyway. Omni cannot decrypt with a
passphrase-protected key.

### Batch Mode (Headless/Low Entropy Systems)

On minimal VMs or containers, interactive key generation may hang waiting for
entropy. Use batch mode:

```bash
# Install rng-tools if entropy is low
sudo apt-get install rng-tools
sudo rngd -r /dev/urandom

# Create batch config
cat > /tmp/gpg-batch << EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: cert
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: encrypt
Name-Real: Omni
Name-Comment: etcd encryption
Name-Email: your@email.com
Expire-Date: 0
%commit
EOF

# Generate
gpg --batch --generate-key /tmp/gpg-batch

# Clean up
rm /tmp/gpg-batch
```

### Key Must Be Accessible to Omni Container

Place `omni.asc` where the container can read it. In the docker-compose setup:

```yaml
volumes:
  - ./omni.asc:/omni.asc:ro
```

The `:ro` mount is fine—Omni only reads the key.

### Don't Lose This Key

If you lose `omni.asc` and don't have the key in your GPG keyring,
you **cannot decrypt existing Omni data**. Back it up securely.

Consider:

- Storing in a password manager (1Password, Infisical)
- Encrypted backup to separate storage
- Keeping a copy in your GPG keyring (`gpg --import omni.asc` on another machine)

## Rotating Keys

Omni doesn't currently support key rotation without data migration. If you need to rotate:

1. Export all cluster configurations
2. Destroy Omni instance
3. Generate new key
4. Redeploy Omni
5. Re-import configurations

This is disruptive—treat the initial key as long-lived.

## Troubleshooting

### "No secret key" Error

Omni can't find or decrypt with the provided key.

- Verify key file exists at mounted path
- Check key has encryption subkey: `gpg --show-keys omni.asc | grep '\[E\]'`
- Ensure no passphrase protection

### Key Generation Hangs

Insufficient entropy. See "Batch Mode" section above, or:

```bash
# Check available entropy
cat /proc/sys/kernel/random/entropy_avail

# Generate activity to increase entropy
find / -type f 2>/dev/null | head -1000 > /dev/null &
```

### GPG Agent Caching Issues

If testing interactively and GPG agent caches a passphrase:

```bash
gpgconf --kill gpg-agent
```
