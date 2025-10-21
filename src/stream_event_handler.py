
from azure.ai.agents.models import (
    MessageDeltaChunk,
    RequiredMcpToolCall,
    RunStepActivityDetails,
    SubmitToolApprovalAction,
    ThreadMessage,
    ThreadRun,
    RunStep,
    ToolApproval,
    AsyncAgentEventHandler,
    McpTool
)
from azure.ai.agents.aio import AgentsClient
from utilities import Utilities


class MyEventHandler(AsyncAgentEventHandler):

    def __init__(self, agents_client: AgentsClient, mcp_tool: McpTool = None) -> None:
        super().__init__()
        self.agents_client = agents_client
        self.mcp_tool = mcp_tool
        self.util = Utilities()

    async def on_message_delta(self, delta: "MessageDeltaChunk") -> None:
        self.util.log_token_blue(delta.text)
   
    async def on_thread_message(self, message: "ThreadMessage") -> None:
        # Add newline after assistant message is complete
        if message.role == "assistant":
            print()

    async def on_thread_run(self, run: "ThreadRun") -> None:
        if isinstance(run.required_action, SubmitToolApprovalAction):
            tool_calls = run.required_action.submit_tool_approval.tool_calls
            if not tool_calls:
                print("No tool calls provided - cancelling run")
                await self.agents_client.runs.cancel(thread_id=run.thread_id, run_id=run.id)
                return

            tool_approvals = []
            for tool_call in tool_calls:
                if isinstance(tool_call, RequiredMcpToolCall):
                    try:
                        print(f"Approving tool call: {tool_call}")
                        tool_approvals.append(
                            ToolApproval(
                                tool_call_id=tool_call.id,
                                approve=True,
                                headers=self.mcp_tool.headers,
                            )
                        )
                    except Exception as e:
                        print(f"Error approving tool_call {tool_call.id}: {e}")

                print(f"tool_approvals: {tool_approvals}")
            if tool_approvals:
                await self.agents_client.runs.submit_tool_outputs_stream(
                    thread_id=run.thread_id, run_id=run.id, tool_approvals=tool_approvals, event_handler=self
                )

    async def on_run_step(self, step: "RunStep") -> None:
        print()
        print(f"Step {step.id} status: {step.status}")

        # Check if there are tool calls in the step details
        step_details = step.get("step_details", {})
        tool_calls = step_details.get("tool_calls", [])

        if tool_calls:
            print("  MCP Tool calls:")
            for call in tool_calls:
                print(f"    Tool Call ID: {call.get('id')}")
                print(f"    Type: {call.get('type')}")

        if isinstance(step_details, RunStepActivityDetails):
            for activity in step_details.activities:
                for function_name, function_definition in activity.tools.items():
                    print(
                        f'  The function {function_name} with description "{function_definition.description}" will be called.:'
                    )
                    if len(function_definition.parameters) > 0:
                        print("  Function parameters:")
                        for argument, func_argument in function_definition.parameters.properties.items():
                            print(f"      {argument}")
                            print(f"      Type: {func_argument.type}")
                            print(f"      Description: {func_argument.description}")
                    else:
                        print("This function has no parameters")

    async def on_done(self) -> None:
        """Handle completion of the entire stream."""
        print()  # Add final newline after everything is complete
   