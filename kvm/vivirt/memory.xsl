<?xml version="1.0"?>
<!-- add cpu -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="xml" indent="yes"/>

	<!-- the main template -->
	<xsl:param name="kb">65536</xsl:param>
	<xsl:param name="mb"/>
	<xsl:param name="gb"/>


	<!-- replace  -->
	<xsl:template match="/domain/memory">
		<xsl:element name="memory">
			<xsl:choose>
				<xsl:when test="$gb">
					<xsl:value-of select="1024 * 1024 * $gb"/>
				</xsl:when>
				<xsl:when test="$mb">
					<xsl:value-of select="1024 * $mb"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$kb"/>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:element>
	</xsl:template>

	<!-- copy all other nodes and attributes -->
	<xsl:template match="node()|@*">
	  <xsl:copy>
	      <xsl:apply-templates select="node()|@*"/>
          </xsl:copy>
	</xsl:template>
</xsl:stylesheet>
