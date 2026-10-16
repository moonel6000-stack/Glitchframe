# GlitchFrame V0.1

Effet de glitch d'écran **aléatoire et temporaire** pour jailbreak, activé par une tuile **Glitch** du Centre de contrôle.

## Ce que ça fait

- Bursts irréguliers de 1 à 9 frames (tears horizontaux, split RGB, blocs volés, roll vertical, canal coupé, inversion, bruit), séparés par des silences aléatoires de 0,25 à 12 s.
- Fonctionne dans SpringBoard et les apps UIKit, via une fenêtre overlay transparente, sans interaction.

## Ce que ça ne fait pas

- Aucun filtre permanent : entre deux bursts l'overlay est caché et vide.
- Photos intactes : rien n'est enregistré, aucun snapshot écrit sur disque (RAM uniquement, libérée après chaque burst).
- Désactivé = fenêtre retirée et buffers libérés immédiatement. Seul état persisté : le booléen `enabled` (défaut off).

## Prérequis

- iPhone avec jailbreak **iOS 17 rootless ou roothide**, injection de tweaks **ElleKit**.
- **CCSupport** (`com.opa334.ccsupport`, repo opa334).
- iPhone 15 Pro : arm64e. Un iPhone stock ne peut pas l'installer.
- roothide : n'injecte aucun tweak dans les apps par défaut, il faut l'activer pour les apps voulues.

## Installer (build GitHub, rien à compiler en local)

1. Pousser le dépôt sur GitHub : le workflow **Build** se lance seul.
2. Récupérer les `.deb` : onglet **Actions** → dernier run → artefact `glitchframe-debs`.
3. Ou publier une Release : créer le tag `v0.1.0` (`git tag v0.1.0 && git push origin v0.1.0`). Les deux `.deb` sont attachés à la Release.
4. Installer le `.deb` qui correspond à ton jailbreak (rootless : `iphoneos-arm64`, roothide : `iphoneos-arm64e`), puis respring.
5. Réglages → Centre de contrôle → ajouter **Glitch**, puis activer la tuile.

## Build local

```
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

Pour roothide en local, utiliser le Theos de `roothide/theos`. SDK : iPhoneOS 16.5, deployment target 15.0, archs arm64 + arm64e.

## CI

`.github/workflows/build.yml` : runner `macos-latest` uniquement, action `waruhachi/theos-action@v2.6.3` (dernier tag v2, vérifié le 14/10/2026), Theos `roothide/theos`. Si le link **arm64e** échoue (ABI), le job échoue volontairement : la slice n'est jamais retirée en silence. Lire l'erreur du linker dans le log et corriger la cause.

Si le run reste en échec avec « capacity constraints » ou « job was not acquired », c'est une panne de runners GitHub : relancer avec **Re-run all jobs**.

## Limites

- Les surfaces hors processus (certaines vidéos, contenus WebContent distants) peuvent être absentes du snapshot de la key window ; le burst retombe alors sur des bandes abstraites.
- Quand une app est au premier plan, SpringBoard et l'app peuvent glitcher indépendamment.
- Non testé sur appareil.

## Licence

MIT
