from __future__ import annotations


def format_schema(schema_rows: list[dict]) -> str:
    """
    Convert database metadata into an LLM-friendly schema description.
    """

    if not schema_rows:
        return "No dataset schema is available."

    datasets: dict[str, dict] = {}

    for row in schema_rows:
        dataset_name = row["dataset_name"]

        if dataset_name not in datasets:
            datasets[dataset_name] = {
                "display_name": row["dataset_display_name"],
                "description": row["dataset_description"],
                "schema": row["database_schema"],
                "engine": row["database_engine"],
                "tables": {},
            }

        tables = datasets[dataset_name]["tables"]

        table_name = row["table_name"]

        if table_name not in tables:
            tables[table_name] = {
                "display_name": row["table_display_name"],
                "description": row["table_description"],
                "columns": [],
            }

        tables[table_name]["columns"].append(row)

    lines = []

    for dataset_name, dataset in datasets.items():
        lines.append(f"DATASET: {dataset_name}")

        if dataset["description"]:
            lines.append(
                f"DESCRIPTION: {dataset['description']}"
            )

        lines.append(
            f"DATABASE SCHEMA: {dataset['schema']}"
        )

        lines.append(
            f"DATABASE ENGINE: {dataset['engine']}"
        )

        for table_name, table in dataset["tables"].items():
            lines.append("")
            lines.append(
                f"TABLE: {dataset['schema']}.{table_name}"
            )

            if table["description"]:
                lines.append(
                    f"TABLE DESCRIPTION: "
                    f"{table['description']}"
                )

            lines.append("COLUMNS:")

            for column in table["columns"]:
                line = (
                    f"- {column['column_name']}: "
                    f"{column['logical_data_type']} "
                    f"({column['physical_data_type']})"
                )

                if column["semantic_role"]:
                    line += (
                        f" | role={column['semantic_role']}"
                    )

                if column["sample_value"] is not None:
                    line += (
                        f" | sample={column['sample_value']}"
                    )

                if column["is_primary_key"]:
                    line += " | PRIMARY KEY"

                if column["is_foreign_key"]:
                    line += " | FOREIGN KEY"

                lines.append(line)

    return "\n".join(lines)