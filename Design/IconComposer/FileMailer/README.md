# Icône FileMailer

Le document source utilisé par Xcode et par l’application distribuée dans le DMG
est [`App/Resources/FileMail.icon`](../../../App/Resources/FileMail.icon).
Ouvrir ce paquet dans Icon Composer pour modifier l’icône. Le nom sélectionné
dans `project.yml` est `FileMail`.

Le fichier [`Design/FileMailerIcon.png`](../../FileMailerIcon.png) est un export
direct d’Icon Composer : plateforme iOS/macOS, apparence Default, 1024 pt, 1×.
Il conserve le rendu natif et sert de logo au README GitHub. Après un nouvel
export à cet emplacement, lancer depuis la racine du dépôt :

```sh
zsh Scripts/generate_app_icon.sh
```

Cette commande met à jour les PNG de l’ancien catalogue `AppIcon.appiconset`
avec la même icône. Le document `.icon` reste la source de l’icône compilée.

[`Design/FileMailerIcon.svg`](../../FileMailerIcon.svg) et
[`FileMailerIcon.svg`](FileMailerIcon.svg) sont les prévisualisations vectorielles
statiques. Elles reprennent les tracés, l’ordre des calques et leur translation
dans le document `.icon`, sur un fond sombre arrondi. Les effets d’éclairage,
d’ombre et de matériau propres à macOS sont conservés dans le document `.icon`
et son export PNG.

Les fichiers `01-Background.svg`, `02-WhitePlane.svg` et `03-BluePlane.svg`
conservent les éléments vectoriels de départ, sur un canevas de 1024 × 1024.
Le document final place le calque blanc au-dessus du bleu et applique aux deux
une translation de `(-13.659437189567257, 3.4607383646631433)` points.

Couleurs des calques : blanc `#FFFFFF`, bleu `#0A84FF`. Le fond du document
Icon Composer utilise la couleur système `system-dark`.
