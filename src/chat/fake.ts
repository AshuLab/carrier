import { ChatRefused, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner } from './runner.ts';

/**
 * A conversation that plays what a test tells it: `reply` runs on each message sent, `emit` plays an event any time
 * (a turn ends on cue, an approval is asked and stays pending until `answer` is called).
 */
export class FakeConversation implements ChatConversation {
  options: ChatOption[] = [];
  nativeId: string | undefined;
  sent: string[] = [];
  answers: { approvalId: string; choiceId: string }[] = [];
  closed = false;
  /** Events to play when a message arrives. */
  reply: (text: string, conversation: FakeConversation) => void = () => {};
  private listeners: ((event: ChatEvent) => void)[] = [];

  send(text: string) {
    this.sent.push(text);
    this.reply(text, this);
  }
  answer(approvalId: string, choiceId: string) {
    this.answers.push({ approvalId, choiceId });
    this.emit({ kind: 'approval_answered', approvalId, choiceId });
  }
  interrupts = 0;
  /** Plays what the provider does on an interrupt; by default nothing, as an adapter that never says the turn ended. */
  onInterrupt: (conversation: FakeConversation) => void = () => {};
  async interrupt() {
    this.interrupts++;
    this.onInterrupt(this);
  }
  async setOption(id: string, value: string) {
    const option = this.options.find((o) => o.id === id);
    if (option) option.current = value;
    this.emit({ kind: 'option', id, value });
  }
  async close() {
    this.closed = true;
  }
  onEvent(listener: (event: ChatEvent) => void) {
    this.listeners.push(listener);
  }
  emit(...events: ChatEvent[]) {
    for (const event of events) for (const listener of this.listeners) listener(event);
  }
}

/** A runner with no provider behind it: it hands out `FakeConversation`s and remembers what it was asked. */
export class FakeChatRunner implements ChatRunner {
  opened: Parameters<ChatRunner['open']>[0][] = [];
  conversations: FakeConversation[] = [];
  /** Set to make `open` refuse, as a provider that is not installed does. */
  refuseWith: string | undefined;
  /** Applied to each new conversation, to script its answers. */
  setup: (conversation: FakeConversation) => void = () => {};

  async open(args: Parameters<ChatRunner['open']>[0]) {
    this.opened.push(args);
    if (this.refuseWith !== undefined) throw new ChatRefused(this.refuseWith);
    const conversation = new FakeConversation();
    this.setup(conversation);
    this.conversations.push(conversation);
    return conversation;
  }
}
