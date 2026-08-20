"use client";

/** The /assistant route. The chat itself lives in src/assistant/AssistantChat
 *  so the dashboard's Ask Sanvya panel can run the very same one, embedded. */
import { AssistantChat } from "../../src/assistant/AssistantChat";

export default function AssistantPage() {
  return <AssistantChat />;
}
