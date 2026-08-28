from __future__ import annotations

import os
from typing import Any

import pandas as pd
import plotly.express as px
import requests
import streamlit as st


# ============================================================
# Configuration
# ============================================================

DEFAULT_API_URL = os.getenv(
    "DATAPILOT_API_URL",
    "http://127.0.0.1:8000",
)

API_URL = DEFAULT_API_URL.rstrip("/")

QUERY_ENDPOINT = (
    f"{API_URL}/api/v1/query"
)

UPLOAD_ENDPOINT = (
    f"{API_URL}/api/v1/datasets/upload"
)

REQUEST_TIMEOUT = 120


# ============================================================
# Page Configuration
# ============================================================

st.set_page_config(
    page_title="DataPilot",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded",
)


# ============================================================
# Custom CSS
# ============================================================

st.markdown(
    """
    <style>

    .block-container {
        max-width: 1200px;
        padding-top: 2rem;
        padding-bottom: 4rem;
    }

    .datapilot-title {
        font-size: 2.6rem;
        font-weight: 700;
        margin-bottom: 0.2rem;
    }

    .datapilot-subtitle {
        color: #6b7280;
        font-size: 1.05rem;
        margin-bottom: 2rem;
    }

    .answer-card {
        padding: 1.5rem;
        border-radius: 14px;
        border: 1px solid rgba(128, 128, 128, 0.25);
        margin-top: 1rem;
        margin-bottom: 1rem;
    }

    .answer-label {
        font-size: 0.8rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: #6b7280;
        margin-bottom: 0.5rem;
    }

    .mode-badge {
        display: inline-block;
        padding: 0.25rem 0.65rem;
        border-radius: 999px;
        font-size: 0.75rem;
        font-weight: 700;
        text-transform: uppercase;
        background: rgba(99, 102, 241, 0.12);
        margin-bottom: 0.8rem;
    }

    .citation-card {
        padding: 0.9rem 1rem;
        border-radius: 10px;
        border: 1px solid rgba(128, 128, 128, 0.2);
        margin-bottom: 0.6rem;
    }

    .small-muted {
        color: #6b7280;
        font-size: 0.85rem;
    }

    </style>
    """,
    unsafe_allow_html=True,
)


# ============================================================
# Session State
# ============================================================

if "query_response" not in st.session_state:
    st.session_state.query_response = None

if "uploaded_file" not in st.session_state:
    st.session_state.uploaded_file = None

if "upload_response" not in st.session_state:
    st.session_state.upload_response = None

if "example_question" not in st.session_state:
    st.session_state.example_question = ""


# ============================================================
# API Helpers
# ============================================================


def _extract_error(response: requests.Response) -> str:
    """
    Extract a useful error message from FastAPI.
    """

    try:
        payload = response.json()
    except ValueError:
        return (
            f"Request failed with HTTP "
            f"{response.status_code}."
        )

    detail = payload.get("detail")

    if isinstance(detail, dict):
        return detail.get(
            "error",
            str(detail),
        )

    if isinstance(detail, str):
        return detail

    if isinstance(payload, dict):
        return payload.get(
            "error",
            str(payload),
        )

    return str(payload)


def check_backend() -> bool:
    """
    Check whether FastAPI is reachable.
    """

    try:
        response = requests.get(
            f"{API_URL}/health",
            timeout=5,
        )

        return response.ok

    except requests.RequestException:
        return False


def upload_dataset(
    uploaded_file: Any,
) -> dict[str, Any]:
    """
    Upload a CSV/XLS/XLSX file to FastAPI.
    """

    files = {
        "file": (
            uploaded_file.name,
            uploaded_file.getvalue(),
            uploaded_file.type
            or "application/octet-stream",
        )
    }

    response = requests.post(
        UPLOAD_ENDPOINT,
        files=files,
        timeout=REQUEST_TIMEOUT,
    )

    if not response.ok:
        raise RuntimeError(
            _extract_error(response)
        )

    payload = response.json()

    if not isinstance(payload, dict):
        raise RuntimeError(
            "Backend returned an invalid upload response."
        )

    return payload


def ask_datapilot(
    question: str,
) -> dict[str, Any]:
    """
    Send a natural-language question to DataPilot.
    """

    response = requests.post(
        QUERY_ENDPOINT,
        json={
            "question": question,
        },
        timeout=REQUEST_TIMEOUT,
    )

    if not response.ok:
        raise RuntimeError(
            _extract_error(response)
        )

    payload = response.json()

    if not isinstance(payload, dict):
        raise RuntimeError(
            "Backend returned an invalid query response."
        )

    return payload


# ============================================================
# Visualization
# ============================================================


def render_visualization(
    visualization: dict[str, Any] | None,
    result: dict[str, Any] | None,
) -> None:
    """
    Render visualization metadata returned by the backend.

    The backend remains responsible for deciding what chart
    should be used. The frontend is only responsible for
    rendering it.
    """

    if not visualization:
        return

    if not result:
        return

    chart_type = visualization.get(
        "type",
        "table",
    )

    x_column = visualization.get("x")
    y_column = visualization.get("y")

    rows = result.get(
        "rows",
        [],
    )

    columns = result.get(
        "columns",
        [],
    )

    if not rows:
        return

    dataframe = pd.DataFrame(
        rows,
        columns=columns,
    )

    if dataframe.empty:
        return

    st.subheader(
        visualization.get(
            "title",
            "Query Results",
        )
    )

    # --------------------------------------------------------
    # Metric
    # --------------------------------------------------------

    if chart_type == "metric":

        if y_column and y_column in dataframe.columns:

            value = dataframe[y_column].iloc[0]

            st.metric(
                label=y_column,
                value=str(value),
            )

        return

    # --------------------------------------------------------
    # Bar
    # --------------------------------------------------------

    if (
        chart_type == "bar"
        and x_column in dataframe.columns
        and y_column in dataframe.columns
    ):

        figure = px.bar(
            dataframe,
            x=x_column,
            y=y_column,
            title=visualization.get(
                "title",
                "Query Results",
            ),
        )

        st.plotly_chart(
            figure,
            use_container_width=True,
        )

        return

    # --------------------------------------------------------
    # Line
    # --------------------------------------------------------

    if (
        chart_type == "line"
        and x_column in dataframe.columns
        and y_column in dataframe.columns
    ):

        figure = px.line(
            dataframe,
            x=x_column,
            y=y_column,
            markers=True,
            title=visualization.get(
                "title",
                "Query Results",
            ),
        )

        st.plotly_chart(
            figure,
            use_container_width=True,
        )

        return

    # --------------------------------------------------------
    # Scatter
    # --------------------------------------------------------

    if (
        chart_type == "scatter"
        and x_column in dataframe.columns
        and y_column in dataframe.columns
    ):

        figure = px.scatter(
            dataframe,
            x=x_column,
            y=y_column,
            title=visualization.get(
                "title",
                "Query Results",
            ),
        )

        st.plotly_chart(
            figure,
            use_container_width=True,
        )

        return

    # --------------------------------------------------------
    # Table fallback
    # --------------------------------------------------------

    st.dataframe(
        dataframe,
        use_container_width=True,
        hide_index=True,
    )


# ============================================================
# Header
# ============================================================

st.markdown(
    '<div class="datapilot-title">📊 DataPilot</div>',
    unsafe_allow_html=True,
)

st.markdown(
    """
    <div class="datapilot-subtitle">
    AI Data Analyst — ask questions about your structured
    data and documents using natural language.
    </div>
    """,
    unsafe_allow_html=True,
)


# ============================================================
# Sidebar
# ============================================================

with st.sidebar:

    st.header("DataPilot")

    backend_online = check_backend()

    if backend_online:
        st.success(
            "Backend connected"
        )
    else:
        st.error(
            "Backend unavailable"
        )

    st.caption(
        f"API: {API_URL}"
    )

    st.divider()

    st.subheader(
        "Upload structured data"
    )

    uploaded_file = st.file_uploader(
        "CSV or Excel file",
        type=[
            "csv",
            "xlsx",
            "xls",
        ],
        help=(
            "Upload a structured dataset "
            "to make it available for SQL analysis."
        ),
    )

    if uploaded_file is not None:

        if (
            st.session_state.uploaded_file
            != uploaded_file.name
        ):

            st.session_state.uploaded_file = (
                uploaded_file.name
            )
            st.session_state.upload_response = None

        if st.button(
            "Upload dataset",
            type="primary",
            use_container_width=True,
        ):

            if not backend_online:
                st.error(
                    "Start the FastAPI backend first."
                )

            else:

                with st.spinner(
                    "Ingesting dataset..."
                ):

                    try:

                        result = upload_dataset(
                            uploaded_file
                        )

                        st.session_state.upload_response = (
                            result
                        )

                        st.success(
                            "Dataset uploaded successfully."
                        )

                    except Exception as exc:

                        st.error(
                            str(exc)
                        )

    if st.session_state.upload_response:

        upload_data = (
            st.session_state
            .upload_response
            .get("data", {})
        )

        if isinstance(
            upload_data,
            dict,
        ):

            st.caption(
                "Latest ingestion"
            )

            for key in (
                "table_name",
                "dataset_id",
                "row_count",
                "column_count",
            ):

                if key in upload_data:

                    st.write(
                        f"**{key}:** "
                        f"{upload_data[key]}"
                    )

    st.divider()

    st.subheader(
        "Example questions"
    )

    example_questions = [
        "Which product generated the highest revenue?",
        "Show total revenue by product.",
        "What are the main findings discussed in the report?",
        "Summarize the recommendations in the report.",
    ]

    for example in example_questions:

        if st.button(
            example,
            use_container_width=True,
        ):

            st.session_state.example_question = (
                example
            )

    st.divider()

    st.caption(
        "DataPilot MVP"
    )


# ============================================================
# Query Section
# ============================================================

st.header(
    "Ask DataPilot"
)

question = st.text_area(
    "Ask anything about your data or documents",
    value=st.session_state.example_question,
    placeholder=(
        "e.g. Which product generated "
        "the highest revenue?"
    ),
    height=100,
)

ask_button = st.button(
    "Ask DataPilot →",
    type="primary",
    use_container_width=True,
)


# ============================================================
# Execute Query
# ============================================================

if ask_button:

    cleaned_question = question.strip()

    if not cleaned_question:

        st.warning(
            "Please enter a question."
        )

    elif not backend_online:

        st.error(
            "DataPilot backend is unavailable. "
            "Start FastAPI with:"
        )

        st.code(
            "uvicorn backend.main:app --reload"
        )

    else:

        with st.spinner(
            "DataPilot is analyzing your question..."
        ):

            try:

                response = ask_datapilot(
                    cleaned_question
                )

                st.session_state.query_response = (
                    response
                )

            except requests.Timeout:

                st.error(
                    "The request timed out. "
                    "Please try again."
                )

            except requests.RequestException as exc:

                st.error(
                    f"Could not connect to DataPilot: {exc}"
                )

            except Exception as exc:

                st.error(
                    str(exc)
                )


# ============================================================
# Results
# ============================================================

response = st.session_state.query_response

if response:

    st.divider()

    success = response.get(
        "success",
        False,
    )

    if not success:

        st.error(
            response.get(
                "error",
                "DataPilot could not answer the question.",
            )
        )

    else:

        mode = response.get(
            "mode",
            "unknown",
        )

        answer = response.get(
            "answer"
        )

        confidence = response.get(
            "confidence"
        )

        # ----------------------------------------------------
        # Answer
        # ----------------------------------------------------

        st.markdown(
            '<div class="answer-card">',
            unsafe_allow_html=True,
        )

        st.markdown(
            '<div class="answer-label">Answer</div>',
            unsafe_allow_html=True,
        )

        st.markdown(
            f'<span class="mode-badge">{mode}</span>',
            unsafe_allow_html=True,
        )

        if answer:

            st.markdown(
                f"### {answer}"
            )

        else:

            st.info(
                "DataPilot did not generate a textual answer."
            )

        st.markdown(
            "</div>",
            unsafe_allow_html=True,
        )

        # ----------------------------------------------------
        # Metadata
        # ----------------------------------------------------

        metadata_columns = st.columns(3)

        with metadata_columns[0]:

            st.metric(
                "Mode",
                mode.upper(),
            )

        with metadata_columns[1]:

            if confidence is not None:

                st.metric(
                    "Confidence",
                    f"{float(confidence) * 100:.0f}%",
                )

            else:

                st.metric(
                    "Confidence",
                    "N/A",
                )

        with metadata_columns[2]:

            latency = response.get(
                "latency_ms"
            )

            if latency is not None:

                if latency >= 1000:

                    latency_text = (
                        f"{latency / 1000:.1f}s"
                    )

                else:

                    latency_text = (
                        f"{latency:.0f}ms"
                    )

            else:

                latency_text = "N/A"

            st.metric(
                "Latency",
                latency_text,
            )

        # ----------------------------------------------------
        # Key Points
        # ----------------------------------------------------

        key_points = response.get(
            "key_points",
            [],
        )

        if key_points:

            st.subheader(
                "Key points"
            )

            for point in key_points:

                st.markdown(
                    f"- {point}"
                )

        # ----------------------------------------------------
        # Visualization
        # ----------------------------------------------------

        result = response.get(
            "result"
        )

        visualization = response.get(
            "visualization"
        )

        if result:

            st.divider()

            render_visualization(
                visualization,
                result,
            )

            rows = result.get(
                "rows",
                [],
            )

            if rows:

                with st.expander(
                    "View result data"
                ):

                    dataframe = pd.DataFrame(
                        rows,
                        columns=result.get(
                            "columns",
                            [],
                        ),
                    )

                    st.dataframe(
                        dataframe,
                        use_container_width=True,
                        hide_index=True,
                    )

        # ----------------------------------------------------
        # SQL
        # ----------------------------------------------------

        sql = response.get(
            "sql"
        )

        if sql:

            with st.expander(
                "SQL"
            ):

                st.code(
                    sql,
                    language="sql",
                )

                sql_explanation = response.get(
                    "sql_explanation"
                )

                if sql_explanation:

                    st.caption(
                        sql_explanation
                    )

        # ----------------------------------------------------
        # Analysis
        # ----------------------------------------------------

        analysis = response.get(
            "analysis"
        )

        if analysis:

            with st.expander(
                "Analysis details"
            ):

                analysis_columns = st.columns(
                    3
                )

                with analysis_columns[0]:

                    st.metric(
                        "Rows",
                        analysis.get(
                            "row_count",
                            0,
                        ),
                    )

                with analysis_columns[1]:

                    st.metric(
                        "Columns",
                        analysis.get(
                            "column_count",
                            0,
                        ),
                    )

                with analysis_columns[2]:

                    st.metric(
                        "Result",
                        (
                            "Empty"
                            if analysis.get(
                                "empty",
                                False,
                            )
                            else "Available"
                        ),
                    )

                numeric_summary = analysis.get(
                    "numeric_summary",
                    {},
                )

                if numeric_summary:

                    st.write(
                        "Numeric summary"
                    )

                    summary_rows = []

                    for column, values in (
                        numeric_summary.items()
                    ):

                        summary_rows.append(
                            {
                                "column": column,
                                **values,
                            }
                        )

                    st.dataframe(
                        pd.DataFrame(
                            summary_rows
                        ),
                        use_container_width=True,
                        hide_index=True,
                    )

        # ----------------------------------------------------
        # Citations
        # ----------------------------------------------------

        citations = response.get(
            "citations",
            [],
        )

        if citations:

            st.divider()

            st.subheader(
                "Sources"
            )

            for index, citation in enumerate(
                citations,
                start=1,
            ):

                source = citation.get(
                    "source",
                    "Unknown source",
                )

                page = citation.get(
                    "page"
                )

                score = citation.get(
                    "score"
                )

                citation_text = (
                    f"**{index}. {source}**"
                )

                if page is not None:

                    citation_text += (
                        f" — Page {page}"
                    )

                if score is not None:

                    citation_text += (
                        f" · Relevance "
                        f"{float(score):.4f}"
                    )

                st.markdown(
                    citation_text
                )

        # ----------------------------------------------------
        # Request metadata
        # ----------------------------------------------------

        request_id = response.get(
            "request_id"
        )

        if request_id:

            st.caption(
                f"Request ID: `{request_id}`"
            )