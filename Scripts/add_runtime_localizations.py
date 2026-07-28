#!/usr/bin/env python3

import json
from pathlib import Path


CATALOG = (
    Path(__file__).resolve().parents[1]
    / "App/Resources/Localizable.xcstrings"
)

ENGLISH = {
    "activé": "enabled",
    "autorisation requise": "approval required",
    "indisponible": "unavailable",
    "désactivé": "disabled",
    "inconnu": "unknown",
    "Sur l’appareil": "On Device",
    "Appareil non éligible": "Device Not Eligible",
    "Désactivé": "Disabled",
    "Modèle pas encore prêt": "Model Not Ready",
    "Modèle en préparation": "Model Preparing",
    "Autorisation d’envoi accordée": "Send Permission Granted",
    "Autorisation d’envoi manquante": "Send Permission Missing",
    "Prêt à rédiger": "Ready to Write",
    "Préparation du brouillon": "Preparing Draft",
    "Analyse du contenu des fichiers": "Analysing File Contents",
    "Apple Intelligence réfléchit": "Apple Intelligence Is Thinking",
    "Rédaction de l’objet et du message": "Writing Subject and Message",
    "Brouillon prêt à relire": "Draft Ready to Review",
    "Lecture du nom et du contenu des fichiers…": "Reading File Names and Contents…",
    "Apple Intelligence prépare le brouillon…": "Apple Intelligence Is Preparing the Draft…",
    "Préparation locale du brouillon…": "Preparing the Draft Locally…",
    "Rédaction de l’objet et du message…": "Writing Subject and Message…",
    "Vérification des pièces jointes…": "Checking Attachments…",
    "Construction du message…": "Building Message…",
    "Envoi avec Gmail…": "Sending with Gmail…",
    "Message envoyé": "Message Sent",
    "Une application macOS open source pour préparer et relire chaque envoi depuis le Finder.": "An open source macOS app for preparing and reviewing every message sent from Finder.",
    "Local par défaut": "Local by Default",
    "L’analyse et la génération Apple Intelligence restent sur votre Mac. Le message et ses pièces jointes vont uniquement chez Google au moment où vous appuyez sur Envoyer.": "Analysis and Apple Intelligence generation stay on your Mac. The message and its attachments go to Google only when you press Send.",
    "Activez l’extension Finder": "Enable the Finder Extension",
    "macOS exige une activation manuelle. FileMailer n’injecte aucun code dans le Finder.": "macOS requires manual activation. FileMailer does not inject code into Finder.",
    "Ajoutez un compte Gmail": "Add a Gmail Account",
    "Le navigateur système s’ouvrira avec les seules autorisations nécessaires à l’envoi.": "The system browser will open with only the permissions required to send.",
    "Ajoutez vos destinataires": "Add Your Recipients",
    "Épinglez vos contacts principaux et choisissez leur ordre dans le menu Finder.": "Pin your main contacts and choose their order in the Finder menu.",
    "Gérer les destinataires": "Manage Recipients",
    "Lancement à la connexion": "Open at Login",
    "FileMailer est configuré pour démarrer à la connexion.": "FileMailer is configured to open at login.",
    "Ce choix reste facultatif et modifiable dans les réglages.": "This option is optional and can be changed in Settings.",
    "Désactiver": "Disable",
    "Activer": "Enable",
    "Essayez avec un fichier non sensible": "Try a Non-Sensitive File",
    "Choisissez un fichier de test. Une fenêtre de composition s’ouvrira, sans jamais envoyer automatiquement.": "Choose a test file. A compose window will open without ever sending automatically.",
    "Le modèle Foundation Models est disponible sur cet appareil.": "The Foundation Models model is available on this device.",
    "Cet appareil n’est pas éligible. Le brouillon déterministe et la rédaction manuelle restent disponibles.": "This device is not eligible. The deterministic draft and manual writing remain available.",
    "Apple Intelligence est désactivé. Vous pourrez l’activer plus tard dans Réglages Système.": "Apple Intelligence is disabled. You can enable it later in System Settings.",
    "Le modèle est en préparation. FileMailer utilisera le fallback déterministe entre-temps.": "The model is preparing. FileMailer will use its deterministic fallback in the meantime.",
    "Reconnecter": "Reconnect",
    "Par défaut": "Default",
    "Retirer ce compte ?": "Remove This Account?",
    "Révoquer et supprimer": "Revoke and Remove",
    "Supprimer localement": "Remove Locally",
    "Annuler": "Cancel",
    "Extension Finder": "Finder Extension",
    "Heartbeat": "Heartbeat",
    "Dernier snapshot": "Latest Snapshot",
    "Absent": "Absent",
    "Schéma IPC": "IPC Schema",
    "Rapport nettoyé": "Sanitised Report",
    "Copié": "Copied",
    "Copier le rapport": "Copy Report",
    "Impossible de terminer l’opération": "Unable to Complete the Operation",
    "Indiquez comment réécrire le message…": "Describe How to Rewrite the Message…",
    "Relancer": "Rewrite",
    "Relancer la rédaction avec cette instruction": "Rewrite Using This Instruction",
    "Fermer l’instruction de réécriture": "Close Rewrite Instruction",
    "Régénérer": "Regenerate",
    "Arrêter la rédaction": "Stop Writing",
    "Donner une instruction à Apple Intelligence": "Give Apple Intelligence an Instruction",
    "Envoi…": "Sending…",
    "Envoi en cours": "Sending",
    "Envoyer le message": "Send Message",
    "Envoie le message visible après validation": "Sends the visible message after review",
    "Compte expéditeur": "Sender Account",
    "Masquer Cc": "Hide Cc",
    "Masquer Cci": "Hide Bcc",
    "Copie": "Cc",
    "Copie cachée": "Bcc",
    "Ajoutez un objet": "Add a Subject",
    "Aucune pièce jointe": "No Attachments",
    "Ajouter une pièce jointe": "Add Attachment",
    "Appliquer la suggestion": "Apply Suggestion",
    "Traitement local": "Local Processing",
    "Apple Intelligence sur ce Mac": "Apple Intelligence on This Mac",
    "Le nom est requis.": "Name Is Required.",
    "Épingler": "Pin",
    "Désépingler": "Unpin",
    "Erreur": "Error",
    "Ajouter": "Add",
    "Enregistrer": "Save",
}


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    locales = sorted(
        {
            locale
            for value in catalog["strings"].values()
            for locale in value.get("localizations", {})
        }
    )
    for source, english in ENGLISH.items():
        item = catalog["strings"].setdefault(source, {})
        localizations = item.setdefault("localizations", {})
        for locale in locales:
            localizations.setdefault(
                locale,
                {
                    "stringUnit": {
                        "state": "translated",
                        "value": english,
                    }
                },
            )
    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
