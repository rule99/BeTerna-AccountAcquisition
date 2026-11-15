export function Legend() {
  return (
    <ul className="legend" aria-label="Legend">
      <li><span className="swatch status-orange" aria-hidden="true" />No contacts</li>
      <li><span className="swatch status-red" aria-hidden="true" />At least one contact without contact information</li>
    </ul>
  );
}
