# Import libraries
from dotenv import load_dotenv
from PyPDF2 import PdfReader
from langchain_postgres import PGVector
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_aws import BedrockEmbeddings
from langchain_aws import ChatBedrock
from langchain_core.prompts import PromptTemplate
from langchain_core.messages import HumanMessage, AIMessage
from langchain_core.memory import BaseMemory
from langchain.chains import ConversationalRetrievalChain
import streamlit as st
import boto3
from PIL import Image
import os
import traceback
from typing import Dict, Any, List
from htmlTemplates import css

class SimpleChatMemory(BaseMemory):
    """A simple chat memory implementation that doesn't require token counting."""
    chat_history: List = []
    
    def clear(self):
        """Clear memory contents."""
        self.chat_history = []
    
    @property
    def memory_variables(self) -> List[str]:
        """Return memory variables."""
        return ["chat_history"]
    
    def load_memory_variables(self, inputs: Dict[str, Any]) -> Dict[str, Any]:
        """Load memory variables."""
        return {"chat_history": self.chat_history}
    
    def save_context(self, inputs: Dict[str, Any], outputs: Dict[str, Any]) -> None:
        """Save context from this conversation to buffer."""
        if inputs.get("question") and outputs.get("answer"):
            self.chat_history.append(HumanMessage(content=inputs["question"]))
            self.chat_history.append(AIMessage(content=outputs["answer"]))

def get_pdf_text(pdf_docs):
    """Extract text from uploaded PDF documents."""
    text = ""
    try:
        for pdf in pdf_docs:
            pdf_reader = PdfReader(pdf)
            for page in pdf_reader.pages:
                text += page.extract_text()
        return text
    except Exception as e:
        st.error(f"Error processing PDF: {str(e)}")
        return None

def get_text_chunks(text):
    """Split text into smaller chunks for processing."""
    if not text:
        return None
        
    # Optimized chunk size for Claude 3 Sonnet
    text_splitter = RecursiveCharacterTextSplitter(
        separators=["\n\n", "\n", ".", " "],
        chunk_size=1000,
        chunk_overlap=200,
        length_function=len
    )
    return text_splitter.split_text(text)

def get_vectorstore(text_chunks):
    """Create vector store using Bedrock Embeddings and pgvector."""
    try:
        embeddings = BedrockEmbeddings(
            model_id="amazon.titan-embed-text-v2:0",
            client=BEDROCK_CLIENT,
            region_name="us-west-2"
        )
        
        if text_chunks is None:
            return PGVector(
                connection=connection,
                embeddings=embeddings,
                use_jsonb=True
            )
            
        return PGVector.from_texts(
            texts=text_chunks,
            embedding=embeddings,
            connection=connection
        )
    except Exception as e:
        st.error(f"Error creating vector store: {str(e)}")
        return None

def get_conversation_chain(vectorstore):
    """Create conversation chain using Bedrock's Claude 3 Sonnet."""
    if not vectorstore:
        return None
        
    try:
        llm = ChatBedrock(
            model_id="anthropic.claude-3-sonnet-20240229-v1:0",
            client=BEDROCK_CLIENT,
            model_kwargs={
                "temperature": 0.5,
                "max_tokens": 8192,
                "top_p": 0.9,
                "top_k": 250
            }
        )
        
        prompt_template = """Human: You are a helpful AI assistant powered by Claude 3 Sonnet. Your role is to provide clear, concise answers using only the information from the context below.

        Guidelines for your responses:
        - Use English and maintain a professional yet conversational tone
        - Start responses with "Based on the provided context: "
        - Answer questions directly using only relevant details from the context
        - If the context doesn't contain the answer, say "I apologize, but I don't find information about that in the provided context. Could you rephrase your question?"
        - Use bullet points for clarity when appropriate
        - Provide a brief summary at the end
        
        Context: {context}

        Question: {question}
        
        Assistant: """

        PROMPT = PromptTemplate(
            template=prompt_template,
            input_variables=["context", "question"]
        )
        
        memory = SimpleChatMemory()
        
        conversation_chain = ConversationalRetrievalChain.from_llm(
            llm=llm,
            chain_type="stuff",
            return_source_documents=True,
            retriever=vectorstore.as_retriever(
                search_type="similarity",
                search_kwargs={"k": 3, "include_metadata": True}
            ),
            get_chat_history=lambda h: h,
            memory=memory,
            combine_docs_chain_kwargs={'prompt': PROMPT}
        )
        
        return conversation_chain.invoke
    except Exception as e:
        st.error(f"Error creating conversation chain: {str(e)}")
        return None

def handle_userinput(user_question):
    """Process user input and generate response."""
    if not user_question.strip():
        st.warning("Please enter a question.")
        return
        
    if "chat_history" not in st.session_state:
        st.session_state.chat_history = []
    
    try:
        with st.spinner("Thinking..."):
            response = st.session_state.conversation({'question': user_question})
            
            # Update chat history
            st.session_state.chat_history = response.get('chat_history', [])
            
            # Display messages with improved formatting
            for message in st.session_state.chat_history:
                if isinstance(message, HumanMessage):
                    st.success(message.content, icon="🤔")
                else:
                    st.markdown(message.content)
                    
    except Exception as e:
        st.error("I encountered an error processing your question. Please try rephrasing it or uploading your documents again.")
        print(f"Error: {str(e)}")
        print(traceback.format_exc())

def main():
    # Page configuration
    st.set_page_config(
        page_title="Gen AI Q&A - Powered by Claude 3 Sonnet",
        layout="wide",
        page_icon="🤖"
    )
    st.write(css, unsafe_allow_html=True)

    with st.sidebar:
        logo_url = "static/Powered-By_logo-stack_RGB_REV.png"
        st.image(logo_url, width=150)
        
        st.markdown("""
        ### Quick Start Guide
        1. 📄 Upload your PDF files
        2. 🔄 Click 'Process'
        3. 💬 Ask questions about your documents
        """)

    # Initialize session state
    if "conversation" not in st.session_state:
        st.session_state.conversation = get_conversation_chain(get_vectorstore(None))
    if "chat_history" not in st.session_state:
        st.session_state.chat_history = None

    # Main content
    st.header("🤖 Generative AI Q&A powered by Claude 3 Sonnet")
    st.markdown(
        '<p style="font-size: 16px;">Leveraging '
        '<a href="https://aws.amazon.com/bedrock/">Amazon Bedrock</a> and '
        '<a href="https://github.com/pgvector/pgvector">pgvector</a> '
        'for intelligent document analysis</p>',
        unsafe_allow_html=True
    )

    # Display architecture diagram
    image = Image.open("static/RAG_APG.png")
    st.image(image, caption='Architecture Overview')

    # Input section
    user_question = st.text_input(
        "Ask about your documents:",
        placeholder="What would you like to know?",
        key="question_input"
    )
    
    col1, col2 = st.columns([1, 5])
    with col1:
        go_button = st.button("🔍 Search", type="primary")

    if go_button or user_question:
        handle_userinput(user_question)

    # Sidebar document upload section
    with st.sidebar:
        st.subheader("📁 Document Upload")
        pdf_docs = st.file_uploader(
            "Upload PDFs and click 'Process'",
            type="pdf",
            accept_multiple_files=True
        )
        
        if st.button("🔄 Process", type="primary"):
            with st.spinner("Processing documents..."):
                raw_text = get_pdf_text(pdf_docs)
                if raw_text:
                    text_chunks = get_text_chunks(raw_text)
                    if text_chunks:
                        vectorstore = get_vectorstore(text_chunks)
                        if vectorstore:
                            st.session_state.conversation = get_conversation_chain(vectorstore)
                            st.success('Documents processed successfully!', icon="✅")
                        else:
                            st.error("Error creating vector store")
                    else:
                        st.error("Error creating text chunks")
                else:
                    st.error("Error processing PDFs")

        st.divider()
        
        # Sample questions
        st.markdown("""
        ### 💡 Sample Questions
        1. What are pgvector's capabilities in Aurora PostgreSQL?
        2. Explain Optimized Reads
        3. How do Aurora Optimized Reads improve performance?
        4. What are Bedrock agents?
        5. How does Knowledge Bases handle document chunking?
        6. Which vector databases work with Knowledge Bases?
        """)

if __name__ == '__main__':
    try:
        load_dotenv()
        
        # Initialize AWS Bedrock client
        BEDROCK_CLIENT = boto3.client("bedrock-runtime", 'us-west-2')
        
        # Database connection string
        connection = f"postgresql+psycopg://{os.getenv('PGUSER')}:{os.getenv('PGPASSWORD')}@{os.getenv('PGHOST')}:{os.getenv('PGPORT')}/{os.getenv('PGDATABASE')}"
        
        main()
    except Exception as e:
        st.error(f"Application initialization error: {str(e)}")
