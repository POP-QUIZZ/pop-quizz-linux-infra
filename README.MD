# Pop-Quizz — Infrastructure & Continuous Delivery

Repository dédié à l'infrastructure et au déploiement de **Pop-Quizz**.

L'objectif est de mettre en place un workflow CI/CD simple et traçable, séparant la **construction des versions** de leur **déploiement**.

---

## 🏗️ Architecture du workflow

```text
┌──────────────────┐
│  Frontend /      │
│  Backend repos   │
└────────┬─────────┘
         │
         │ Push / Pull Request
         ▼
┌─────────────────────────────┐
│            CI               │
│                             │
│  • Lint & quality checks    │
│  • Tests unitaires (Jest)   │
│  • Analyse statique         │
│    (SonarQube/SonarCloud)   │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│      Build & Publish        │
│                             │
│  • Docker build             │
│  • Image versionnée         │
│  • Publication Docker Hub   │
└─────────────┬───────────────┘
              │
              │ Version disponible
              ▼
        ┌─────────────┐
        │   Registry  │
        │  Docker Hub │
        └──────┬──────┘
               │
               │ Choix explicite
               │ d'une version
               ▼
┌─────────────────────────────┐
│     Continuous Delivery     │
│                             │
│ workflow_dispatch           │
│                             │
│ frontend_tag = <SHA>        │
│ backend_tag  = <SHA>        │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│          Ansible            │
│                             │
│  Déploiement de la version  │
│  sélectionnée sur la VM     │
└─────────────────────────────┘
```

---

## 🔄 CI — Validation et construction

Les repositories frontend et backend disposent de pipelines permettant de valider chaque modification avant de produire une version déployable.

### Contrôles qualité

- Linting
- Tests unitaires avec **Jest**
- Analyse statique du code avec **SonarQube / SonarCloud**

L'objectif est de détecter les erreurs et problèmes de qualité avant la création de l'artefact.

### Build & Publish

Une fois les contrôles validés sur `main` :

1. L'image Docker est construite.
2. Elle est identifiée par le SHA du commit.
3. Elle est publiée sur **Docker Hub**.

Exemple :

```text
pop-quizz-back:a83f71c...
pop-quizz-front:7c91abc...
```

Le SHA permet de relier précisément une image Docker au code source qui l'a produite.

---

## 📦 Release candidate

Une image publiée dans le registry constitue une **version disponible pour le déploiement**.

Elle n'est pas automatiquement déployée.

Par exemple :

```text
Backend
commit: a83f71c
        ↓
CI
        ↓
Docker build
        ↓
Docker Hub
        ↓
pop-quizz-back:a83f71c
```

Cette version peut alors être sélectionnée pour un déploiement.

---

## 🚀 Continuous Delivery

Le déploiement est volontairement séparé de la phase de CI.

Le repository d'infrastructure fournit un workflow GitHub Actions déclenché manuellement avec `workflow_dispatch`.

L'opérateur sélectionne explicitement les versions à déployer :

```text
Frontend tag : 7c91abc
Backend tag  : a83f71c
```

Le workflow transmet ensuite ces versions à **Ansible**, qui déploie les images correspondantes sur l'infrastructure cible.

```text
Docker Hub
    │
    │ versions sélectionnées
    ▼
workflow_dispatch
    │
    ▼
Ansible
    │
    ▼
VM
```

Cette approche permet de conserver une séparation claire entre :

- **CI** : vérifier et construire
- **Registry** : stocker les versions produites
- **Delivery** : choisir explicitement une version et la rendre déployable
- **Deployment** : appliquer cette version sur l'infrastructure

---

## 🎯 Traçabilité

Chaque déploiement est associé à des versions d'images identifiables par leur SHA.

Exemple :

```text
Production
├── Frontend : 7c91abc
└── Backend  : a83f71c
```

Il est ainsi possible de retrouver précisément quelles versions du frontend et du backend sont exécutées sur l'environnement cible.

---

## 🛠️ Technologies

- GitHub Actions
- Docker
- Docker Hub
- Ansible
- Git
- Jest
- SonarQube / SonarCloud
- Linux

---

## 📌 Principe retenu

Le projet privilégie une approche **Continuous Delivery** :

```text
Code
  ↓
Quality & Tests
  ↓
Build
  ↓
Versioned Docker Image
  ↓
Docker Hub
  ↓
Human decision
  ↓
Ansible
  ↓
Deployment
```

Le déploiement n'est donc pas déclenché automatiquement par chaque modification du code. Une version précise doit être explicitement sélectionnée avant d'être déployée.
