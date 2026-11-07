# goldbox

This branch is upstream Free Pascal fixes_3_2 at `c118291bbde00708229f10f653ca2f4a506292e0`, plus this directory and `.github/workflows/goldbox.yml`. Upstream's own
CI workflows are removed here, so that pushing this branch runs only goldbox.yml.

Pushing the tag `goldbox` builds the pins in `toolchain` with `fpc-setup.sh` and publishes them as the release
`goldbox`: one archive per platform and a `SHA256SUMS`. Deleting the tag deletes the release. The Gold Box
reconstructions (talonius/bc-pool-of-radiance and others) download their toolchain from that release instead of
building it in every CI run.

`fpc-setup.sh` and `toolchain-release.sh` are copies of Pool of Radiance's `scripts/` files of the same names; change
them there and copy them here. To build another version: change `toolchain` (and the recipe, if the way it is built
changed), commit, and move the tag:

    git tag -f goldbox && git push -f origin goldbox
