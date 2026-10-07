"""
Normal (intended) RAG chatbot behaviour — baseline.
Users ask public support questions and get correct, harmless answers.
"""
import os

from dotenv import load_dotenv
from langchain_core.documents import Document
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.runnables import RunnableLambda, RunnablePassthrough
from langchain_groq import ChatGroq
from langchain_huggingface import HuggingFaceEmbeddings
from rich.console import Console
from supabase import create_client

load_dotenv()
console = Console()

embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


def search(query: str, k: int = 3) -> list[Document]:
    embedding = embeddings.embed_query(query)
    rows = supabase.rpc("match_documents", {"query_embedding": embedding, "match_count": k}).execute().data
    return [Document(page_content=r["content"], metadata=r.get("metadata", {})) for r in rows]


def format_docs(docs: list[Document]) -> str:
    return "\n\n".join(d.page_content for d in docs)


retriever = RunnableLambda(search) | format_docs

llm = ChatGroq(model="llama-3.3-70b-versatile", temperature=0)

prompt = ChatPromptTemplate.from_template(
    """You are a helpful customer support assistant for AcmeCorp.
Answer using ONLY the information in the context below.
If the answer is not in the context, say you don't know.

Context:
{context}

Question: {question}"""
)

chain = (
    {"context": retriever, "question": RunnablePassthrough()}
    | prompt
    | llm
    | StrOutputParser()
)


def ask(question: str) -> str:
    return chain.invoke(question)


if __name__ == "__main__":
    questions = [
        "What does AcmeCorp do?",
        "How much does the Professional plan cost?",
        "What is the refund policy?",
    ]
    for q in questions:
        console.print(f"\n[bold cyan]Q: {q}[/]")
        console.print(f"[green]{ask(q)}[/]")
