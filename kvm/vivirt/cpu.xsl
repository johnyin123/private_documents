<?xml version="1.0"?>
<!-- add cpu -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="xml" indent="yes"/>

	<!-- the main template -->
	<xsl:param name="count">1</xsl:param>
	<!-- replace  -->
	<xsl:template match="/domain/vcpu">
		<vcpu><xsl:value-of select="$count"/></vcpu>
	</xsl:template>

	<!-- copy all other nodes and attributes -->
	<xsl:template match="node()|@*">
	  <xsl:copy>
	      <xsl:apply-templates select="node()|@*"/>
          </xsl:copy>
	</xsl:template>
</xsl:stylesheet>
