# Genesys Data Client

Don't treat the proposed client as though it were becoming the UI for **Genesys.Core itself**. That's not what you're building.

Here is the model:

```text
                         Genesys Cloud
                              │
                   ┌──────────┴──────────┐
                   │                     │
              Live APIs              Notifications
                   │                     │
                   └──────────┬──────────┘
                              │
                       ┌──────▼──────┐
                       │ Genesys.Core│
                       │             │
                       │ API facade  │
                       │ SDK/services│
                       │ auth        │
                       │ paging      │
                       │ retry       │
                       │ models      │
                       │ catalog     │
                       │ analytics   │
                       │ utilities   │
                       └──────┬──────┘
                              │
             ┌────────────────┼────────────────┐
             │                │                │
       Real Genesys      Mock Server      Test Fixtures
       Cloud mode        Offline mode
             │                │
             └────────┬───────┘
                      │
              SAME APP CONTRACT
                      │
     ┌────────────────┼──────────────────────┐
     │                │                      │
 Existing apps   App templates        Genesys Data Client
     │                                       │
 AuditLogsConsole                            │
 ConversationAnalysis                       │
 InvestigationConsole                       │
 MonthlyMetrics                             │
 OpsConsole                                 │
 ShortCallAnalysis                          │
 ...                                        │
                                             ▼
                                   generalized data
                                      workbench
```

## Genesys.Core should remain what it is

I would **not add Node, React, Vite, or any UI-specific dependency to Core itself**.

Current philosophy remains intact:

> **Genesys.Core provides the reusable Genesys Cloud application substrate.**

The mock server is then not "what Core is." It is another capability of Core:

> **A high-fidelity offline implementation of the interface applications normally receive from Genesys Cloud.**

That is particularly valuable because an application should be able to move between:

```text
Genesys Cloud
     ↕
Genesys.Core
     ↕
Application
```

and:

```text
Genesys.Core Mock
        ↕
Application
```

without the application fundamentally knowing or caring which side is supplying the data.

That is a very strong architecture.

---

# The new thing is an application

Introduce:

```text
apps/
├── AuditLogsConsole/
├── ConversationAnalysis/
├── ConversationAnalyzer/
├── GenesysInterrogator/
├── InvestigationConsole/
├── MonthlyMetrics/
├── OpsConsole/
├── Parse-SipTrace/
├── ShortCallAnalysis/
│
├── GenesysDataClient/          <-- new
│
└── templates/
    └── ...
```

And **GenesysDataClient gets its own frontend toolchain**.

Something like:

```text
apps/GenesysDataClient/
│
├── package.json
├── vite.config.ts
├── tsconfig.json
│
├── src/
│   ├── app/
│   ├── core/
│   ├── features/
│   ├── components/
│   ├── pages/
│   ├── reports/
│   ├── dashboards/
│   └── visualization/
│
├── tests/
└── dist/
```

Now Node isn't a Genesys.Core dependency.

It is a **GenesysDataClient development dependency**.

---

## I pick Vite + React + TypeScript

Question:

> How sophisticated should one of the applications built on Genesys.Core be allowed to become?

Answer:

**As sophisticated as necessary.**

There's no architectural virtue in forcing every Core consumer to inherit Core's implementation constraints.

Someone could build:

```text
PowerShell app
.NET desktop app
React app
Angular app
Vue app
Python app
CLI
Grafana integration
Power BI integration
service
agent
automation
```

against Core.

That's part of the value of having Core.

The **reference/template application** can remain deliberately minimal, while Genesys Data Client demonstrates what a much more capable consumer can look like.

---

Instead of:

```text
Agent
    interactions
    status
    queues

Supervisor
    workforce
    monitoring
    performance

Administrator
    configuration
    routing
    users
    integrations
```

This application would instead center on:

```text
                       DATA
                        │
        ┌───────────────┼───────────────┐
        │               │               │
     Explore         Analyze          Build
        │               │               │
    records          metrics         reports
    objects          trends          dashboards
    APIs             correlations    exports
    events           anomalies       views
```

That's a different product category.

## Description

> **Genesys Data Client is a customizable data exploration, analysis, reporting, and visualization application built on Genesys.Core. It provides a unified interface to Genesys Cloud data without imposing the agent, supervisor, or administrative workflows of the native Genesys Cloud client.**

---

## The Existing apps matter

Looking at the `apps/` directory, we've already effectively performed a series of experiments:

```text
AuditLogsConsole
        ↓
"What does audit investigation need?"

ConversationAnalysis
ConversationAnalyzer
        ↓
"What does conversation investigation need?"

InvestigationConsole
        ↓
"What does generalized troubleshooting need?"

MonthlyMetrics
        ↓
"What does reporting need?"

OpsConsole
        ↓
"What does operational visibility need?"

Parse-SipTrace
        ↓
"What does protocol-level analysis need?"

ShortCallAnalysis
        ↓
"What does specialized anomaly analysis need?"
```

Genesys Data Client doesn't necessarily replace them.

It **extracts the common interaction model that those applications revealed**.

That's an important distinction.

There are several purpose-built applications showing you the recurring primitives.

I suspect those primitives will turn out to be things like:

```text
Data source
    ↓
Query
    ↓
Filter
    ↓
Transform
    ↓
Group / Aggregate
    ↓
Display
    ↓
Investigate
    ↓
Visualize
    ↓
Export
    ↓
Save as view/report
```

And _that_ becomes the application's foundation.

---

## Separate three concepts

This will prevent the new app from becoming another giant monolith.

### 1. Core

Knows Genesys.

```text
Genesys.Core

"How do I interact with Genesys Cloud?"
```

Core owns things such as:

- authentication
- API catalog
- requests
- pagination
- retries
- models
- normalization
- Genesys-specific semantics
- mock behavior
- fixtures
- analytics helpers

### 2. Data Client engine

Knows how to work with data.

```text
GenesysDataClient

"What can the user do with the data Core provides?"
```

It owns:

- tables
- filtering
- sorting
- grouping
- column selection
- saved views
- layouts
- dashboards
- visualization
- reporting
- exporting
- workspace state

### 3. Feature modules

Know particular problem domains.

```text
Conversation Explorer
Audit Explorer
Queue Analytics
User Explorer
Flow Explorer
Operational Health
Short Call Analysis
SIP Investigation
etc.
```

Those use both of the layers above.

That produces this:

```text
┌──────────────────────────────────────────────────────┐
│                 Genesys Data Client                  │
│                                                      │
│ ┌────────────┐ ┌────────────┐ ┌───────────────────┐ │
│ │Conversation│ │ Audit Logs │ │ Queue Analytics   │ │
│ │ Explorer   │ │ Explorer   │ │                   │ │
│ └────────────┘ └────────────┘ └───────────────────┘ │
│                                                      │
│ ┌──────────────────────────────────────────────────┐ │
│ │       Common Data Client Capabilities            │ │
│ │                                                  │ │
│ │ Tables │ Charts │ Reports │ Dashboards │ Export │ │
│ │ Filter │ Group  │ Search  │ Saved Views│ Layout │ │
│ └──────────────────────────────────────────────────┘ │
└──────────────────────────┬───────────────────────────┘
                           │
                    Genesys.Core
                           │
                ┌──────────┴──────────┐
                │                     │
          Genesys Cloud          Mock Server
```

That's the architecture we are pursuing.

---

## Template adjustment

Don't convert the existing generic template into React\*\* just because Genesys Data Client uses React.

Preserve two tiers.

```text
apps/
├── templates/
│   ├── basic/
│   │   └── minimal Core consumer
│   │
│   └── web-react/
│       └── Vite + React + TypeScript starter
│
└── GenesysDataClient/
```

The basic template demonstrates:

> "Here's the minimum required to build something on Genesys.Core."

The React template demonstrates:

> "Here's a production-capable web application starting point."

And Genesys Data Client demonstrates:

> "Here's what happens when you take this architecture nearly as far as it can go."

That is a healthy platform story.

---

## Final answer

For **Genesys.Core itself**:

> **Do not introduce Node/npm.**

For **GenesysDataClient**:

> **Use Vite + React + TypeScript and give the application its own isolated frontend toolchain.**

For distribution, I would initially keep `dist/` out of Git and have CI produce a release artifact. You can later decide whether Genesys.Core's launcher should optionally detect and serve that static application, but that should remain an integration convenience rather than making the frontend part of Core.

The larger architectural decision I'd make before substantial UI development is actually **not React vs. something else**. It's defining the reusable **Data Client primitives**—`DataSource`, `QueryDefinition`, `ViewDefinition`, `ReportDefinition`, `DashboardDefinition`, `ExportDefinition`, etc.—because if those contracts are right, your existing specialized apps can gradually donate their best capabilities to this one without producing a giant collection of hard-coded screens.
