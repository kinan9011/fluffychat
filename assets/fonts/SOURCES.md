# Bundled fonts

Static TrueType files, copied unmodified from the upstream repositories at the pinned commits. Both families are licensed under the SIL Open Font License 1.1 (see the `*-OFL.txt` files and `LICENSES/OFL-1.1.txt`). `test/font_assets_test.dart` verifies the checksums below.

| File | Upstream | sha256 |
|---|---|---|
| Figtree-Regular.ttf | https://github.com/erikdkennedy/figtree/blob/032dfa7fe219ef3a02890d6d3add84eacc9aebfe/fonts/ttf/Figtree-Regular.ttf | 448d74e778cc9774db27bd86cf451bba982b2e4dc348f610390eb6e3439cf6ca |
| Figtree-Medium.ttf | same commit, `fonts/ttf/Figtree-Medium.ttf` | 358a4de79ae6c3fd7c6a54fcd778c1101ba376af75b8463e715df6988387bc19 |
| Figtree-SemiBold.ttf | same commit, `fonts/ttf/Figtree-SemiBold.ttf` | 35fc4508d627f8402a7d5ae91d842d1adb36846eea902c0a849642afecd0ac74 |
| Figtree-Bold.ttf | same commit, `fonts/ttf/Figtree-Bold.ttf` | 71a35e2bd92a05427e2dc9897bab41f8a865800e148238007735b5934508198a |
| JetBrainsMono-Regular.ttf | https://github.com/JetBrains/JetBrainsMono/blob/19371302b95d218af43299bce79ddbddd0bc364d/fonts/ttf/JetBrainsMono-Regular.ttf | e6fd0d7e91550b3ed2b735d4312474362c4716edc4fc0577a0f61ed782d5aed1 |
| JetBrainsMono-Bold.ttf | same commit, `fonts/ttf/JetBrainsMono-Bold.ttf` | d22c4f3821d725eb01210d278d95dfcfcaadc34699a06658d47c8a5cc5830ada |
| Figtree-OFL.txt | `OFL.txt` of the Figtree commit | 140d37233e7f3ce7313798befa9600893bcceaf41a55fa0fa5ad52f7f657a268 |
| JetBrainsMono-OFL.txt | `OFL.txt` of the JetBrains Mono commit | a76abf002c49097d146e86740a3105a5d00450b1592e820a1109a8c5680cd697 |

JetBrains Mono 500 is intentionally not bundled (app size); weight 500 renders with the regular face.

Both fonts only cover Latin (plus Cyrillic/Greek for JetBrains Mono); other scripts fall back to system fonts.
