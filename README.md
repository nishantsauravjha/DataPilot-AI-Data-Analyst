# DataPilot

**DataPilot** is an AI-powered data analyst that lets users upload CSV/Excel datasets and ask questions about their data in natural language.

Instead of manually writing SQL or analyzing spreadsheets, users can simply ask:

> **"Which products generated the highest revenue last quarter?"**

DataPilot converts the question into SQL, validates it, executes it against PostgreSQL, analyzes the results with Pandas, generates visualizations when appropriate, and returns a clear natural-language answer.

## 🚀 How It Works

```text
User Question
      ↓
LLM
      ↓
SQL Generation
      ↓
SQL Validation
      ↓
PostgreSQL
      ↓
Pandas Analysis
      ↓
Chart / Insights
      ↓
Natural-Language Answer
```

## ✨ Key Features

* 📂 Upload CSV and Excel datasets
* 💬 Ask questions using natural language
* 🤖 AI-powered SQL generation
* 🛡️ SQL validation and safety checks
* 🐘 PostgreSQL-based data querying
* 🐼 Pandas-powered analysis
* 📊 Automatic data visualization
* 📝 Natural-language insights and explanations
* 🔌 Modular backend architecture

## 🛠️ Tech Stack

* **Python**
* **FastAPI**
* **PostgreSQL**
* **Pandas**
* **OpenAI API**
* **SQLAlchemy**
* **Docker**
* **Pytest**

## 📁 Project Structure

```text
DataPilot/
├── backend/
│   ├── api/
│   ├── core/
│   ├── services/
│   └── ...
├── tests/
├── docker-compose.yml
├── requirements.txt
└── README.md
```

## 🎯 Goal

DataPilot aims to make data analysis accessible to non-technical users by turning complex database queries into a simple **conversation with your data**.

## 📌 Status

**MVP in active development.**

More capabilities such as advanced visualizations, multi-dataset analysis, conversational follow-ups, and richer analytical insights can be added as the project evolves.
