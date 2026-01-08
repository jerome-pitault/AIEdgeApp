# **AIEdgeApp** 📱🤖

**Exécutez des modèles MLX (LLMs et VLMs) en local sur iOS, sans cloud polluant, tout en préservant votre confidentialité.**

---

## **À propos du projet**
**AIEdgeApp** est une **preuve de concept** open source pour explorer comment l’IA peut être **légère, privée et frugale**.  
En tant que **business analyst** travaillant sur des programmes de transformation numérique, j’ai voulu tester une hypothèse :  
*Peut-on exécuter des modèles d’IA performants sur des appareils Apple, **sans dépendre du cloud** (coûteux et énergivore), tout en protégeant la vie privée ?*  

**Résultat** :  
✅ Ça fonctionne, y compris sur un **iPhone 12 Pro Max (2020)**.  
✅ Compatible évidemment avec les derniers modèles (testé sur iPhone 16 Pro Max), mais aussi avec des appareils plus basiques (*quelques limitations sur l’iPhone SE 2022*).  
✅ **Anti-obsolescence** : installez un chatbot local sur un ancien iphone au lieu d'acheter du neuf pour avoir cette fonctionnalité.  
  
---
### **Origine et philosophie**  
- **Ouverture** : Basé sur [MLX Swift](https://github.com/ml-explore/mlx-swift), un framework open source pour l’IA sur iOS/macOS.  
- **Valeurs** :  
  - **Confidentialité** : Vos données restent sur votre appareil.  
  - **Sobriété énergétique** : Pas de data centers, pas de kilowatt-heure par requête.  
  - **Flexibilité** : Un projet *vibe-codé* (voir avertissement ci-dessous) pour explorer librement les possibilités de l’IA locale.  
  
---
  
## **Fonctionnalités clés**

| Fonctionnalité               | Détails                                                                                     |
|------------------------------|---------------------------------------------------------------------------------------------|
| **Téléchargement de modèles** | Importation de modèles MLX (ex: Qwen 2.5, Qwen 3, Granite 4.0, Mistral, etc.).               |
| **Exécution 100% locale**    | Pas de cloud, pas de réseau requis (sauf pour les requêtes web via DuckDuckGo).              |
| **Support LLMs & VLMs**       | Dialogue avec des modèles de langage et visuels (ex: analyse d’images depuis la galerie).  |
| **Optimisé pour iOS**         | Développé pour **Core ML** et **Metal**, compatible iPhone 12 Pro Max et versions ultérieures. |
  
---
  
## **Cas d’usage**
*(Proof of Concept – à vous de jouer pour imaginer la suite !)*
- **Chatbot privé** : Dialoguez avec un LLM sans fuite de données.
- **Génération de texte hors ligne** : Rédaction, brainstorming, etc.
- **Analyse d’images** : Description ou Q&A à partir de photos (VLMs).
- **Requêtes web contextuelles** : Intégration avec DuckDuckGo pour des infos à jour *(optionnel, désactivable)*.
  
---
  
## **Comment démarrer ?**
1. **Clonez le dépôt** :
   ```bash
   git clone https://github.com/jerome-pitault/AIEdgeApp.git
  
2. **Ouvrez le projet dans Xcode** (version **26.2** recommandée).  
3. **Build & Run sur un appareil iOS.**  
4. **Sélectionnez un modèle dans la liste et commencez à dialoguer !**  
  
- Premier chargement : Le téléchargement du modèle peut prendre du temps.  
- Prochaines utilisations : Bien plus rapide (cache local)  
  
## **Structure du projet**  
(Simplifié pour se concentrer sur l’essentiel)  
  
. ContentView.swift : Interface utilisateur (UI).  
. AIEdgeViewModel.swift : Logique métier (gestion des modèles, inférence).  
. ModelRegistry.swift : Registre des modèles personnalisés (LLMs/VLMs).  
  
## **Pourquoi contribuer ?**  
Ce projet est open source et vise à :  
  
. Démocratiser l’IA locale sur iOS.  
. Réduire l’empreinte carbone de l’IA.  
. Prolonger la durée de vie des appareils.  

**Comment aider ?**  
. **Feedback** : Ouvrez une issue pour partager vos retours ou cas d’usage.  
. **Business Analyse** : Vous avez identifié un besoin métier ? Contactez-moi !  

## **⚠️ Avertissement important ⚠️**  
Cette app est **largement "vibe-codée"** (avec l’aide de chatbots et outils d’IA) et **non auditée** pour une utilisation en production.  
  
. **Risques potentiels** : Bugs, crashes, ou comportements inattendus.  
. **Protection iOS** : Le sandboxing limite les dégâts, mais utilisez à vos risques et périls.  
. **Pas de garantie** : Ni pour la stabilité, ni pour la sécurité de vos données.  
(Si vous trouvez un bug ou une faille, merci d’ouvrir une issue !)  
  
## **Licence**  
MIT – Voir LICENSE.  
  
## **Remerciements**  
Inspiré par [MLXSampleApp](https://github.com/ibrahimcetin/MLXSampleApp) et le framework [MLX Swift](https://swiftpackageindex.com/ml-explore/mlx-swift/main/documentation/mlx).  
Merci à [Hugging Face](https://huggingface.co/) pour ses modèles open source.  




