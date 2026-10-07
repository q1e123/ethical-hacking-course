"""
LangGraph ReAct agent with a RAG tool backed by Supabase.
The agent searches the knowledge base before answering customer questions.
"""
import os
from typing import Annotated

from dotenv import load_dotenv
from langchain_core.documents import Document
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_core.tools import tool
from langchain_groq import ChatGroq
from langchain_huggingface import HuggingFaceEmbeddings
from langgraph.graph import StateGraph
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from supabase import create_client
from typing_extensions import TypedDict

load_dotenv()

embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
_supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])

SYSTEM = (
    "You are a helpful customer support agent for AcmeCorp. "
    "Search the knowledge base before answering. Be concise and professional."
)

MODEL = "llama-3.3-70b-versatile"


def _search(query: str, k: int = 3) -> list[Document]:
    embedding = embeddings.embed_query(query)
    rows = _supabase.rpc("match_agent_documents", {"query_embedding": embedding, "match_count": k}).execute().data
    return [Document(page_content=r["content"], metadata=r.get("metadata", {})) for r in rows]


class State(TypedDict):
    messages: Annotated[list, add_messages]


@tool
def search_knowledge_base(query: str) -> str:
    """Search AcmeCorp's knowledge base to find information relevant to the customer's question."""
    docs = _search(query)
    if not docs:
        return "No relevant information found in the knowledge base."
    return "\n\n".join(
        f"[source: {d.metadata.get('source', 'unknown')}]\n{d.page_content}" for d in docs
    )


def build_agent():
    llm = ChatGroq(model=MODEL, temperature=0).bind_tools([search_knowledge_base])

    def call_model(state: State):
        messages = [SystemMessage(content=SYSTEM)] + state["messages"]
        return {"messages": [llm.invoke(messages)]}

    graph = StateGraph(State)
    graph.add_node("agent", call_model)
    graph.add_node("tools", ToolNode([search_knowledge_base]))
    graph.set_entry_point("agent")
    graph.add_conditional_edges("agent", tools_condition)
    graph.add_edge("tools", "agent")
    return graph.compile()


def run_agent(agent, question: str) -> str:
    result = agent.invoke({"messages": [HumanMessage(content=question)]})
    return result["messages"][-1].content
