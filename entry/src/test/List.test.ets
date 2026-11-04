import localUnitTest from './LocalUnit.test';
import knowledgeGraphLayoutTest from './KnowledgeGraphLayout.test';

export default function testsuite() {
  localUnitTest();
  knowledgeGraphLayoutTest();
}
