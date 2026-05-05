function parseIdentityFromFullName(fullName) {
  if (!fullName || typeof fullName !== 'string') {
    return { objectClass: '', shortName: '', nameSource: 'unavailable' };
  }

  const classMatch = fullName.match(/^([^\s]+)\s+/);
  const objectClass = classMatch ? classMatch[1] : '';
  const dotMatch = fullName.match(/\.([^.\s/]+)\s*$/);
  if (dotMatch) {
    return { objectClass, shortName: dotMatch[1], nameSource: 'fullNameFallback' };
  }
  const pathMatch = fullName.match(/\/([^/\s]+)\s*$/);
  if (pathMatch) {
    return { objectClass, shortName: pathMatch[1], nameSource: 'fullNameFallback' };
  }
  return { objectClass, shortName: '', nameSource: 'unavailable' };
}

function extractFullNameFromSummary(summary) {
  if (!summary || typeof summary !== 'string') return '';
  const match = summary.match(/\bfullName=(.*?)(?:\s+name=|\s+nameSource=|$)/);
  return match ? match[1].trim() : '';
}

module.exports = {
  parseIdentityFromFullName,
  extractFullNameFromSummary
};
