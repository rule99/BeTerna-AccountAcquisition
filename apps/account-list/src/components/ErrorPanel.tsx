export function ErrorPanel({ message }: { message: string }) {
  return (
    <div className="alert alert-error" role="alert">
      <p>The account list couldn't be loaded. Try Reload; if it keeps failing, contact support with the details below.</p>
      <p className="muted">{message}</p>
    </div>
  );
}
