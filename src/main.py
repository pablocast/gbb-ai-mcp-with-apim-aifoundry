import asyncio
import logging
import os

from azure.ai.agents.aio import AgentsClient
from azure.ai.agents.models import (
    Agent,
    AgentThread,
    AsyncToolSet,
    McpTool,
    CodeInterpreterTool
)
from azure.identity.aio import DefaultAzureCredential
from dotenv import load_dotenv

from stream_event_handler import MyEventHandler
from terminal_colors import TerminalColors as tc
from utilities import Utilities, load_instructions

logging.basicConfig(level=logging.ERROR)
logger = logging.getLogger(__name__)

load_dotenv(override=True)

AGENT_NAME = "AI Foundry Agent with MCP Tools"
API_DEPLOYMENT_NAME = os.getenv("MODEL_DEPLOYMENT_NAME")
PROJECT_ENDPOINT = os.getenv("FOUNDRY_PROJECT_ENDPOINT")
APIM_RESOURCE_GATEWAY_URL = os.getenv("APIM_RESOURCE_GATEWAY_URL")
APIM_SUBSCRIPTIONS_KEY = os.getenv("APIM_SUBSCRIPTIONS_KEY")
MAX_COMPLETION_TOKENS = 10240
MAX_PROMPT_TOKENS = 20480
TEMPERATURE = 0.1
TOP_P = 0.1
INSTRUCTIONS_FILE = None

utilities = Utilities()

agents_client = AgentsClient(
    credential=DefaultAzureCredential(),
    endpoint=PROJECT_ENDPOINT,
)

INSTRUCTIONS_FILE = "instructions.txt"

toolset = AsyncToolSet()

async def add_agent_tools() -> None:
    """Add tools for the agent."""
    code_interpreter_tool = CodeInterpreterTool()

    mcp_server_tool = McpTool(
            server_label="weather",
            server_url=f"{APIM_RESOURCE_GATEWAY_URL}/weather-mcp/sse"
        )

    mcp_server_tool.update_headers(key="Authorization", value=f"Bearer {APIM_SUBSCRIPTIONS_KEY}")
    mcp_server_tool.set_approval_mode("never")

    toolset.add(code_interpreter_tool)
    toolset.add(mcp_server_tool)


async def initialize() -> tuple[Agent, AgentThread]:
    """Initialize the agent with the sales data schema and instructions."""
    if not INSTRUCTIONS_FILE:
        return None, None

    await add_agent_tools()

    try:
        instructions = load_instructions(INSTRUCTIONS_FILE)
     
        print("Creating agent...")
        agent = await agents_client.create_agent(
            model=API_DEPLOYMENT_NAME,
            name=AGENT_NAME,
            instructions=instructions,
            toolset=toolset,
            temperature=TEMPERATURE,
            #headers={"x-ms-enable-preview": "true"},
        )
        print(f"Created agent, ID: {agent.id}")

        print("Creating thread...")
        thread = await agents_client.threads.create()
        print(f"Created thread, ID: {thread.id}")

        return agent, thread

    except Exception as e:
        logger.error("An error occurred initializing the agent: %s", str(e))
        logger.error("Please ensure you've enabled an instructions file.")


async def cleanup(agent: Agent, thread: AgentThread) -> None:
    """Cleanup the resources."""
    existing_files = await agents_client.files.list()
    for f in existing_files.data:
        await agents_client.files.delete(f.id)
    await agents_client.threads.delete(thread.id)
    await agents_client.delete_agent(agent.id)


async def post_message(thread_id: str, content: str, agent: Agent, thread: AgentThread) -> None:
    """Post a message to the Foundry Agent Service."""
    try:
        await agents_client.messages.create(
            thread_id=thread_id,
            role="user",
            content=content,
        )

        async with await agents_client.runs.stream(
            thread_id=thread.id,
            agent_id=agent.id,
            event_handler=MyEventHandler(agents_client=agents_client, mcp_tool=toolset.get_tool(McpTool)),
            max_completion_tokens=MAX_COMPLETION_TOKENS,
            max_prompt_tokens=MAX_PROMPT_TOKENS,
            temperature=TEMPERATURE,
            top_p=TOP_P,
            instructions=agent.instructions,
        ) as stream:
            await stream.until_done()
            print()

    except Exception as e:
        utilities.log_msg_purple(
            f"An error occurred posting the message: {e!s}")


async def main() -> None:
    """
    Example questions: What's the weather in Lisbon, Cairo and London?
    """
    async with agents_client:
        agent, thread = await initialize()
        print("Initialization complete.")
        if not agent or not thread:
            print(f"{tc.BG_BRIGHT_RED}Initialization failed. Ensure you have uncommented the instructions file for the lab.{tc.RESET}")
            print("Exiting...")
            return

        cmd = None

        while True:
            prompt = input(
                f"\n\n{tc.GREEN}Enter your query (type exit or save to finish): {tc.RESET}").strip()
            if not prompt:
                continue

            cmd = prompt.lower()
            if cmd in {"exit", "save"}:
                break

            await post_message(agent=agent, thread_id=thread.id, content=prompt, thread=thread)
           

        if cmd == "save":
            print("The agent has not been deleted, so you can continue experimenting with it in the Azure AI Foundry.")
            print(
                f"Navigate to https://ai.azure.com, select your project, then playgrounds, agents playgound, then select agent id: {agent.id}"
            )
        else:
            await cleanup(agent, thread)
            print("The agent resources have been cleaned up.")


if __name__ == "__main__":
    print("Starting async program...")
    asyncio.run(main())
    print("Program finished.")