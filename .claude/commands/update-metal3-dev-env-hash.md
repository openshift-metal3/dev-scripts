# Update metal3-dev-env Hash

Update the pinned metal3-dev-env commit hash in `01_install_requirements.sh` to the latest commit from the main branch.

## Steps

1. Fetch the latest commit hash from the metal3-dev-env main branch:
   ```bash
   git ls-remote https://github.com/metal3-io/metal3-dev-env.git refs/heads/main | cut -f1
   ```

2. Update the hash in `01_install_requirements.sh` where it says:
   ```bash
   git reset <HASH> --hard
   ```

3. After updating, inform the user of:
   - The old hash that was replaced
   - The new hash that was set
   - Suggest they may want to check the metal3-dev-env changelog for breaking changes

## Important Notes

- The hash is pinned to ensure CI stability and catch breaking changes before they affect everyone
- When updating, also check if ANSIBLE_VERSION needs to be aligned with the new metal3-dev-env version (see https://github.com/metal3-io/metal3-dev-env/blob/master/lib/common.sh)

