/** The reason and the error come from the agent's own output: no control character (ESC included) may reach the terminal. */
export const printable = (text: string) => text.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ');
